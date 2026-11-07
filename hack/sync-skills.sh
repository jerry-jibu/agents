#!/usr/bin/env bash
# sync-skills.sh — agent-skills governance for the jerry-jibu/agents repo.
#
# Data-flow law (docs/designs/multi-harness-agent-repo-governance.md):
#   * The git repo is the SINGLE source of truth; node (~/.agents/skills) is a
#     pure deployment target. Edits happen in the repo; nodes sync via
#     git commit/push/pull. Pull runs on ONE authoritative node only.
#   * pull     upstream -> vendor/github.com/<owner>/<repo>/<skill>/ (+ lock v4)
#              per-skill mirror granularity (upstream-deleted skills survive);
#              never touches in-house/ or vendor/unknown/; auto-restores the
#              pulled skills onto this node afterwards.
#   * collect  node -> repo for node-originated artifacts only (harness
#              configs). Skills are NEVER collected: node-side skill drift is
#              reported by doctor C4 and harvested via explicit adopt.
#   * restore  repo -> node, delta-guarded by lock deployedHash baselines
#              (baseline match = legal forward progress; mismatch = drift).
#   * adopt    node drift -> repo, diffed and confirmed
#              (harvest in-house / promote unknown / fork vendor).
#
# Zones: vendor/ (upstream mirror, pull-only) · vendor/unknown/ (frozen,
#        pull never touches) · in-house/skills/ (self-authored; git is the
#        version record, not the lock).
#
# Lock: .skill-lock.json v4 — sources registry (frozen flags) + per-skill
#       commit anchors + deployedHash baselines (skills + inHouse sections).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$REPO_ROOT/vendor"
UNKNOWN="$VENDOR/unknown"
INHOUSE="$REPO_ROOT/in-house/skills"
NODE_SKILLS="$HOME/.agents/skills"
ZCODE_AGENTS="$HOME/.zcode/agents"
LOCK="$REPO_ROOT/.skill-lock.json"
SOURCES_CONF="$REPO_ROOT/hack/sources.conf"

FORCE=0
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
trim() {
  local s="$*"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# deployedHash baseline algorithm (pinned in the design; sort -z degrades to
# find order when the local sort lacks it — order is tree-deterministic).
if sort -z </dev/null >/dev/null 2>&1; then
  hash_dir() {
    find "$1" -type f ! -name .DS_Store -print0 | sort -z |
      xargs -0 shasum 2>/dev/null | shasum | awk '{print $1}'
  }
else
  hash_dir() {
    find "$1" -type f ! -name .DS_Store -print0 |
      xargs -0 shasum 2>/dev/null | shasum | awk '{print $1}'
  }
fi

url_to_sid() { # git@github.com:owner/repo.git -> github.com/owner/repo
  local u="$1"
  u="${u#git@}"; u="${u#https://}"; u="${u#http://}"
  u="${u%.git}"
  printf '%s' "$u" | sed 's#:#/#'
}

worktree_clean_guard() {
  [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] ||
    die "repo worktree is dirty — commit or stash first (git is the source of truth; see design G1c)"
}

# ---- lock helpers (python3; no jq on this node) -----------------------------

lock_dump_hashes() { # -> "section<TAB>name<TAB>deployedHash" lines
  python3 - "$LOCK" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    raise SystemExit
for sec in ("skills", "inHouse"):
    for name, e in sorted(d.get(sec, {}).items()):
        print(f"{sec}\t{name}\t{e.get('deployedHash','')}")
PY
}

lock_dump_sources() { # -> "name<TAB>source" lines (skills section)
  python3 - "$LOCK" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    raise SystemExit
for name, e in sorted(d.get("skills", {}).items()):
    print(f"{name}\t{e.get('source','')}")
PY
}

lock_apply_hashes() { # $1 = batchfile: "section<TAB>name<TAB>hash"; atomic, no-op when unchanged
  python3 - "$LOCK" "$1" <<'PY'
import json, sys, os
lock, batch = sys.argv[1], sys.argv[2]
d = json.load(open(lock))
changed = False
for line in open(batch):
    line = line.rstrip("\n")
    if not line:
        continue
    sec, name, h = line.split("\t")
    e = d.setdefault(sec, {}).setdefault(name, {})
    if e.get("deployedHash") != h:
        e["deployedHash"] = h
        changed = True
if changed:
    tmp = lock + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, lock)
PY
}

lock_pull_update() { # $1 = batchfile: "name<TAB>source<TAB>commit<TAB>pulledAt"
  python3 - "$LOCK" "$1" <<'PY'
import json, sys, os
lock, batch = sys.argv[1], sys.argv[2]
d = json.load(open(lock))
changed = False
for line in open(batch):
    line = line.rstrip("\n")
    if not line:
        continue
    name, sid, commit, pulled = line.split("\t")
    sec = d.setdefault("skills", {})
    e = sec.setdefault(name, {})
    if e.get("commit") != commit:      # same-version re-pull stays a no-op (idempotency)
        e["zone"] = "vendor"
        e["source"] = sid
        e["commit"] = commit
        e["pulledAt"] = pulled
        changed = True
    e.setdefault("source", sid)
    e.setdefault("zone", "vendor")
if changed:
    tmp = lock + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, lock)
PY
}

# ---- delta guard -------------------------------------------------------------

guard_drifts=0
# modes: baseline-vendor (lock skills.deployedHash) · baseline-inhouse
# (lock inHouse.deployedHash) · static (frozen/unknown: repo copy never moves,
# so node-vs-repo direct compare needs no baseline; nothing written to lock)
delta_guard() { # $1=node dir  $2=name  $3=baselines file  $4=mode  $5=repo-src
  local dir="$1" name="$2" baselines="$3" mode="$4" rsrc="$5" base nodehash
  [ -d "$dir" ] || return 0                    # nothing on node yet -> allow
  nodehash="$(hash_dir "$dir")"
  if [ "$mode" = static ]; then
    if [ "$nodehash" != "$(hash_dir "$rsrc")" ]; then
      warn "delta-guard: '$name' (frozen) differs from its repo copy -> drift"
      guard_drifts=$((guard_drifts + 1))
      return 1
    fi
    return 0
  fi
  base="$(awk -F'\t' -v n="$name" '$2==n {print $3}' "$baselines")"
  if [ -z "$base" ]; then
    warn "delta-guard: '$name' exists on node without a deployed baseline -> drift"
    guard_drifts=$((guard_drifts + 1))
    return 1
  fi
  if [ "$nodehash" != "$base" ]; then
    warn "delta-guard: '$name' drifts from its deployed baseline -> drift"
    guard_drifts=$((guard_drifts + 1))
    return 1
  fi
  return 0                                     # baseline match = legal forward progress
}

# ---- pull ---------------------------------------------------------------------

cmd_pull() { # [source-id...]   e.g. github.com/google/elephant-goldfish-model
  worktree_clean_guard
  local args=("$@")
  local workdir statedir plan pullbatch
  workdir="$(mktemp -d "${TMPDIR:-/tmp}/skill-sources.XXXXXX")"
  statedir="$(mktemp -d "${TMPDIR:-/tmp}/skill-sync.XXXXXX")"
  plan="$statedir/restore.plan"; : > "$plan"
  pullbatch="$statedir/pull.batch"; : > "$pullbatch"
  local url subdir shared src sid commit vdir s sub d name now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  while IFS='|' read -r url subdir shared; do
    case "$url" in ''|'#'*) continue ;; esac
    url="$(trim "$url")"; subdir="$(trim "$subdir")"; shared="$(trim "$shared")"
    sid="$(url_to_sid "$url")"
    if [ "${#args[@]}" -gt 0 ]; then
      case " ${args[*]} " in *" $sid "*) ;; *) continue ;; esac
    fi
    log "source: $url ($sid)"
    src="$workdir/$(basename "$url" .git)"
    git clone --quiet --depth 1 "$url" "$src" || die "clone failed: $url"
    commit="$(git -C "$src" rev-parse HEAD)"
    vdir="$VENDOR/$sid"
    mkdir -p "$vdir"
    IFS=',' read -r -a subdirs <<< "${subdir:-.}"
    for sub in ${subdirs[@]+"${subdirs[@]}"}; do
      sub="$(trim "$sub")"
      [ -n "$sub" ] || continue
      [ -d "$src/$sub" ] || { warn "no $sub/ in $url"; continue; }
      while IFS= read -r skillmd; do
        d="$(dirname "$skillmd")"
        name="$(basename "$d")"
        # vendor-vs-vendor collision: same install-name owned by another source
        if existing="$(awk -F'\t' -v n="$name" '$1==n {print $2}' "$statedir/names.src" 2>/dev/null)" &&
           [ -n "$existing" ] && [ "$existing" != "$sid" ]; then
          die "install-name collision: '$name' already owned by '$existing' (fork into in-house/skills/ with a new name, then retry)"
        fi
        printf '%s\t%s\n' "$name" "$sid" >> "$statedir/names.src"
        rsync -a --delete "$d/" "$vdir/$name/"
        IFS=',' read -r -a shared_dirs <<< "${shared:-}"
        for s in ${shared_dirs[@]+"${shared_dirs[@]}"}; do
          s="$(trim "$s")"
          [ -n "$s" ] || continue
          [ -d "$src/$s" ] && rsync -a --delete "$src/$s/" "$vdir/$name/$s/" ||
            warn "shared dir '$s' not found in $url"
        done
        printf '%s\t%s\t%s\t%s\n' "$name" "$sid" "$commit" "$now" >> "$pullbatch"
        printf 'vendor\t%s\t%s\n' "$vdir/$name" "$name" >> "$plan"
        log "  pulled: $name"
      done < <(find "$src/$sub" -maxdepth 4 -name SKILL.md -not -path '*/node_modules/*' | sort)
    done
  done < "$SOURCES_CONF"
  rm -rf "$workdir" "$statedir"

  if [ -s "$pullbatch" ]; then
    lock_pull_update "$pullbatch"
  fi
  if [ -s "$plan" ]; then
    log "materializing pulled skills onto this node (delta-guarded)"
    restore_from_plan "$plan"
  fi
  cmd_agents
  log "pull complete"
}

# ---- restore ------------------------------------------------------------------

restore_from_plan() { # $1 = plan file ("zone<TAB>srcdir<TAB>name"); guard -> materialize -> backfill baselines
  local plan="$1" baselines locknames mode
  baselines="$(mktemp "${TMPDIR:-/tmp}/lock.hash.XXXXXX")"
  lock_dump_hashes > "$baselines"
  locknames="$(mktemp "${TMPDIR:-/tmp}/lock.names.XXXXXX")"
  lock_dump_sources | awk -F'\t' '{print $1}' > "$locknames"
  # pre-scan guards (no writes) so a drift aborts before any materialization
  guard_drifts=0
  local seen=" " zone src name
  while IFS=$'\t' read -r zone src name; do
    case "$seen" in *" $name "*) continue ;; esac
    seen="$seen$name "
    if [ "$zone" = inhouse ]; then mode=baseline-inhouse
    elif grep -qxF "$name" "$locknames"; then mode=baseline-vendor
    else mode=static; fi
    delta_guard "$NODE_SKILLS/$name" "$name" "$baselines" "$mode" "$src" || true
  done < "$plan"
  if [ "$guard_drifts" -gt 0 ] && [ "$FORCE" -ne 1 ]; then
    rm -f "$baselines" "$locknames"
    die "delta guard: $guard_drifts node-side drift(s) — nothing written.
  harvest into git : hack/sync-skills.sh adopt <name>
  discard node copy: hack/sync-skills.sh restore --force   (after confirming discard)"
  fi
  if [ "$guard_drifts" -gt 0 ]; then warn "--force: overwriting $guard_drifts drifted dir(s) (logged)"; fi
  local hashbatch
  hashbatch="$(mktemp "${TMPDIR:-/tmp}/lock.newhash.XXXXXX")"
  local count=0 sec
  while IFS=$'\t' read -r zone src name; do
    rsync -a --delete "$src/" "$NODE_SKILLS/$name/"
    if [ "$zone" = inhouse ]; then
      sec=inHouse
    elif grep -qxF "$name" "$locknames"; then
      sec=skills
    else
      sec=skip   # frozen/unknown: no lock entry (design: frozen entries stay out of lock)
    fi
    if [ "$sec" != skip ]; then
      printf '%s\t%s\t%s\n' "$sec" "$name" "$(hash_dir "$NODE_SKILLS/$name")" >> "$hashbatch"
    fi
    count=$((count + 1))
    if [ "$zone" = inhouse ]; then log "  materialized (in-house): $name"; else log "  materialized: $name"; fi
  done < "$plan"
  lock_apply_hashes "$hashbatch"
  rm -f "$baselines" "$locknames" "$hashbatch"
  log "restored $count skills -> $NODE_SKILLS"
}

cmd_restore() { # [--force] [name...]
  local names=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --force) FORCE=1 ;;
      *) names+=("$1") ;;
    esac
    shift
  done
  local plan
  plan="$(mktemp "${TMPDIR:-/tmp}/restore.plan.XXXXXX")"
  local d
  shopt -s nullglob
  for d in "$VENDOR"/github.com/*/*/*/; do
    if [ -f "$d/SKILL.md" ]; then printf 'vendor\t%s\t%s\n' "$d" "$(basename "$d")" >> "$plan"; fi
  done
  for d in "$UNKNOWN"/*/; do
    if [ -f "$d/SKILL.md" ]; then printf 'vendor\t%s\t%s\n' "$d" "$(basename "$d")" >> "$plan"; fi
  done
  for d in "$INHOUSE"/*/; do
    if [ -f "$d/SKILL.md" ]; then printf 'inhouse\t%s\t%s\n' "$d" "$(basename "$d")" >> "$plan"; fi
  done
  shopt -u nullglob
  if [ "${#names[@]}" -gt 0 ]; then
    local filtered want
    filtered="$(mktemp "${TMPDIR:-/tmp}/restore.filt.XXXXXX")"; : > "$filtered"
    for want in ${names[@]+"${names[@]}"}; do
      awk -F'\t' -v n="$want" '$3==n' "$plan" >> "$filtered"
    done
    mv "$filtered" "$plan"
  fi
  [ -s "$plan" ] || die "nothing to restore (plan empty — check names/zones)"
  restore_from_plan "$plan"
  rm -f "$plan"
}

# ---- adopt --------------------------------------------------------------------

inject_forked_from() { # $1=file $2=value
  awk -v v="$2" '
    NR==1 && $0~/^---[[:space:]]*$/ { print; infm=1; next }
    infm && !done && $0~/^name:[[:space:]]*/ { print; print "forked-from: " v; done=1; next }
    { print }
  ' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

cmd_adopt() { # <skill-name> — harvest/promote/fork the node copy into git
  local name="${1:-}"
  [ -n "$name" ] || die "usage: hack/sync-skills.sh adopt <skill-name>"
  local node="$NODE_SKILLS/$name"
  [ -d "$node" ] || die "no node copy of '$name'"
  local dst="$INHOUSE/$name" mode commit=""
  if [ -d "$INHOUSE/$name" ]; then
    mode="harvest (in-house: node edits -> repo)"
  elif [ -d "$UNKNOWN/$name" ]; then
    mode="promote (unknown -> in-house; git rm the vendor/unknown copy after)"
  else
    mode="fork (vendor -> in-house; upstream updates will no longer apply — forked-from marker added)"
    commit="$(python3 - "$LOCK" "$name" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
e = d.get("skills", {}).get(sys.argv[2], {})
print(f'{e.get("source","?")}@{e.get("commit","?")}')
PY
)"
  fi
  log "adopt $name — $mode"
  if [ -d "$dst" ]; then
    diff -rq "$dst" "$node" || true
  fi
  local reply
  printf 'Adopt the node version into %s? [y/N] ' "$dst"
  read -r reply
  case "$reply" in y*|Y*) ;; *) die "aborted" ;; esac
  mkdir -p "$dst"
  rsync -a --delete "$node/" "$dst/"
  [ "$mode" = fork ] && [ -f "$dst/SKILL.md" ] && [ -n "$commit" ] &&
    inject_forked_from "$dst/SKILL.md" "$commit" || true
  log "adopted: $name -> $dst (commit it with git)"
}

# ---- collect ------------------------------------------------------------------

cmd_collect() { # node -> repo: harness configs only (credential-scanned)
  local spec src dst
  while IFS='|' read -r spec src; do
    case "$spec" in ''|'#'*) continue ;; esac
    src="$(trim "$src")"
    [ -f "$src" ] || continue
    dst="$REPO_ROOT/harness/$spec/config/$(basename "$src")"
    mkdir -p "$(dirname "$dst")"
    if grep -qEi '"(env|headers)"[[:space:]]*:|token|secret|apikey|api_key|password' "$src"; then
      warn "collect: $src looks credential-bearing — skipped (redact manually, then add to repo)"
      continue
    fi
    if cmp -s "$src" "$dst"; then continue; fi
    cp "$src" "$dst"
    log "collected: $src -> harness/$spec/config/"
  done <<EOF
zcode|$HOME/.zcode/cli/config.json
antigravity|$HOME/.gemini/config/mcp.json
antigravity|$HOME/.gemini/config/mcp_config.json
deepseek|$HOME/.deepseek/mcp.json
EOF
  log "note: claude config collection awaits Stage 2 path verification (harness/claude/NOTES.md)"
}

# ---- agents -------------------------------------------------------------------

agent_tools() { # $1=agent name -> ZCode tools allowlist
  case "$1" in
    egm-synthesizer)            echo "[Read, Grep, Glob, Write, Agent]" ;;
    egm-bootstrap-orchestrator) echo "[Read, Grep, Glob, Write, Edit, Agent]" ;;
    *)                          echo "[Read, Grep, Glob]" ;;  # reviewers: read-only
  esac
}

cmd_agents() { # generate user-scope ZCode subagent definitions from skill personas
  local d f fm name desc body out count=0 seen=" "
  mkdir -p "$ZCODE_AGENTS"
  for d in "$NODE_SKILLS"/*/; do
    [ -d "$d/agents" ] || continue
    for f in "$d"/agents/*.md; do
      [ -f "$f" ] || continue
      fm="$(awk 'NR==1&&$0~/^---[[:space:]]*$/{infm=1;next} infm&&$0~/^---[[:space:]]*$/{exit} infm{print}' "$f")"
      [ -n "$fm" ] || continue
      name="$(sed -n 's/^name:[[:space:]]*//p' <<< "$fm" | head -1)"
      [ -n "$name" ] || continue
      case "$seen" in *" $name "*) continue ;; esac
      seen="$seen$name "
      desc="$(sed -n 's/^description:[[:space:]]*//p' <<< "$fm" | head -1)"
      body="$(awk 'NR==1&&$0~/^---[[:space:]]*$/{infm=1;next} infm&&$0~/^---[[:space:]]*$/{infm=0;body=1;next} body{print}' "$f")"
      out="$ZCODE_AGENTS/$name.md"
      {
        echo "---"
        echo "name: $name"
        echo "description: ${desc:-Skill subagent from $(basename "$d")}"
        echo "tools: $(agent_tools "$name")"
        echo "---"
        echo "$body"
      } > "$out"
      count=$((count + 1))
    done
  done
  log "generated $count agent definitions in $ZCODE_AGENTS"
  log "publish with: hack/sync-agents.sh collect && hack/sync-agents.sh deploy"
}

# ---- list ---------------------------------------------------------------------

cmd_list() {
  local d
  for d in "$NODE_SKILLS"/*/; do
    if [ -f "$d/SKILL.md" ]; then basename "$d"; fi
  done | sort
}

usage() {
  cat <<EOF
usage: hack/sync-skills.sh [--force] [command]

commands:
  pull [source-id]  pull declared sources (hack/sources.conf) into vendor/,
                    update lock v4 commit anchors, then restore pulled skills
                    onto this node. Run on the ONE authoritative node only.
  restore [name...] materialize repo (vendor + unknown + in-house) -> node,
                    delta-guarded by lock deployedHash baselines
  adopt <name>      harvest node-side drift into git (in-house harvest /
                    unknown promote / vendor fork with forked-from marker)
  collect           node -> repo harness config backups (credential-scanned)
  agents            regenerate ~/.zcode/agents from skill personas (generate
                    only; publish via sync-agents.sh collect + deploy)
  list              list installed node skills

zones: vendor/github.com/<owner>/<repo>/<skill>/  (pull-only upstream mirror)
       vendor/unknown/<skill>/                    (frozen; pull never touches)
       in-house/skills/<skill>/                   (self-authored; git = version)
EOF
}

case "${1:-}" in
  --force)  FORCE=1; shift; case "${1:-restore}" in restore|"") cmd_restore "$@" ;; *) die "--force applies to restore" ;; esac ;;
  pull)     shift; cmd_pull "$@" ;;
  collect)  cmd_collect ;;
  restore)  shift; cmd_restore "$@" ;;
  adopt)    shift; cmd_adopt "$@" ;;
  agents)   cmd_agents ;;
  list)     cmd_list ;;
  -h|--help|help) usage ;;
  "")       usage ;;
  *)        usage; die "unknown command: $1" ;;
esac
