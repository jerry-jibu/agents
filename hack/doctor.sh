#!/usr/bin/env bash
# doctor.sh — expectation-vs-reality health checks for the agent-skills repo.
#
# v1 (Stage 2): C1-C7. Expectation state comes from harness/<name>/expected.json
# (SSOT: verifiedAt, unverified list, agents/mcp expectations). C7 requires
# --live. Unverified items print UNVERIFIED and never affect the exit code.
# Exit code: number of ERROR findings (0 = green).
#
# Checks: C1 frontmatter (zoned severity) · C2 depends-on resolution ·
#         C3 zcode skills dedup · C4 repo<->node parity + content drift ·
#         C5 lock consistency (entries->dirs, strays) · C6 node strays ·
#         C7 harness expectations + MCP (--live) + verifiedAt expiry.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$REPO_ROOT/vendor"
UNKNOWN="$VENDOR/unknown"
INHOUSE="$REPO_ROOT/in-house/skills"
HARNESS="$REPO_ROOT/harness"
NODE_SKILLS="$HOME/.agents/skills"
ZCODE_SKILLS="$HOME/.zcode/skills"
LOCK="$REPO_ROOT/.skill-lock.json"

LIVE=0; FIX=0; LIST=0
for a in "$@"; do
  case "$a" in
    --live) LIVE=1 ;;
    --fix)  FIX=1 ;;
    --list) LIST=1 ;;
    *) printf 'unknown arg: %s\n' "$a" >&2; exit 2 ;;
  esac
done

err=0; warnn=0; unv=0
log()  { printf '%s\n' "$*"; }
result() { # $1=level $2=check $3=message
  case "$1" in
    ERROR) log "ERROR  [$2] $3"; err=$((err + 1)) ;;
    WARN)  log "WARN   [$2] $3"; warnn=$((warnn + 1)) ;;
    PASS)  log "PASS   [$2] $3" ;;
    UNVERIFIED) log "UNVER [$2] $3"; unv=$((unv + 1)) ;;
    *)     log "INFO   [$2] $3" ;;
  esac
}

# deployedHash algorithm — shared with sync-skills.sh (design: 共用函数)
source "$REPO_ROOT/hack/lib-hash.sh"

# ---- working set ---------------------------------------------------------------
plan="$(mktemp "${TMPDIR:-/tmp}/doctor.plan.XXXXXX")"
baselines="$(mktemp "${TMPDIR:-/tmp}/doctor.base.XXXXXX")"
locksources="$(mktemp "${TMPDIR:-/tmp}/doctor.src.XXXXXX")"
cleanup() { rm -f "$plan" "$baselines" "$locksources" "$deps_all" "$missing" "$HARNESS_EVAL"; }
trap cleanup EXIT
missing="$(mktemp "${TMPDIR:-/tmp}/doctor.missing.XXXXXX")"; : > "$missing"
deps_all="$(mktemp "${TMPDIR:-/tmp}/doctor.deps.XXXXXX")"; : > "$deps_all"
HARNESS_EVAL="$(mktemp "${TMPDIR:-/tmp}/doctor.harness.XXXXXX")"

python3 - "$LOCK" <<'PY' > "$baselines"
import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception: raise SystemExit
for sec in ("skills", "inHouse"):
    for name, e in sorted(d.get(sec, {}).items()):
        print(f"{sec}\t{name}\t{e.get('deployedHash','')}")
PY
python3 - "$LOCK" <<'PY' > "$locksources"
import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception: raise SystemExit
for name, e in sorted(d.get("skills", {}).items()):
    print(f"{name}\t{e.get('source','')}\t{e.get('commit','')}")
for name, e in sorted(d.get("inHouse", {}).items()):
    print(f"{name}\t<inHouse>\t")
PY

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

repo_names="$(awk -F'\t' '{print $3}' "$plan" | sort)"
node_names="$(ls "$NODE_SKILLS" 2>/dev/null | sort)"
total="$(printf '%s\n' "$repo_names" | grep -c . || true)"

# ---- C1: frontmatter (name == dirname; depends-on format; zoned severity) -----
c1_fixable=""
c1_bad=0
while IFS=$'\t' read -r zone src name; do
  fm="$(awk 'NR==1&&$0~/^---[[:space:]]*$/{infm=1;next} infm&&$0~/^---[[:space:]]*$/{exit} infm{print}' "$src/SKILL.md")"
  fmname="$(sed -n 's/^name:[[:space:]]*//p' <<< "$fm" | head -1)"
  dep="$(sed -n 's/^depends-on:[[:space:]]*//p' <<< "$fm" | head -1)"
  if [ -n "$dep" ] && ! printf '%s' "$dep" | grep -qE '^[a-z0-9][a-z0-9-]*(, ?[a-z0-9][a-z0-9-]*)*$'; then
    result WARN c1 "$name: depends-on format invalid: '$dep'"
    c1_bad=$((c1_bad + 1))
  fi
  if [ "$fmname" != "$name" ]; then
    if [ "$zone" = inhouse ]; then
      result ERROR c1 "$name: frontmatter name '$fmname' != dirname (auto-fixable)"
      c1_fixable="$c1_fixable $src/SKILL.md:$name"
    else
      result WARN c1 "$name: frontmatter name '$fmname' != dirname (mirror/frozen — report upstream, never hand-edit)"
    fi
    c1_bad=$((c1_bad + 1))
  fi
done < "$plan"
if [ "$c1_bad" -eq 0 ]; then result PASS c1 "frontmatter ok for $total skills"; fi

# ---- C2: depends-on targets exist (repo) and are deployed (node) ---------------
c2_bad=0
while IFS=$'\t' read -r zone src name; do
  dep="$(sed -n 's/^depends-on:[[:space:]]*//p' "$src/SKILL.md" | head -1)"
  [ -n "$dep" ] || continue
  IFS=',' read -r -a deps <<< "$(printf '%s' "$dep" | tr -d ' ')"
  for depname in ${deps[@]+"${deps[@]}"}; do
    printf '%s\t%s\n' "$name" "$depname" >> "$deps_all"
  done
done < "$plan"
while IFS=$'\t' read -r from dep; do
  if ! printf '%s\n' "$repo_names" | grep -qxF "$dep"; then
    result ERROR c2 "$from depends-on '$dep': not found in any repo zone"
    c2_bad=$((c2_bad + 1))
  elif ! [ -d "$NODE_SKILLS/$dep" ]; then
    result ERROR c2 "$from depends-on '$dep': in repo but NOT deployed"
    printf '%s\n' "$dep" >> "$missing"
    c2_bad=$((c2_bad + 1))
  fi
done < "$deps_all"
if [ "$c2_bad" -eq 0 ]; then result PASS c2 "all depends-on targets exist and are deployed"; fi

# ---- C3: ~/.zcode/skills must not shadow the shared root (default: empty) ------
c3_bad=0
if [ -d "$ZCODE_SKILLS" ]; then
  for d in "$ZCODE_SKILLS"/*; do
    [ -e "$d" ] || continue
    result ERROR c3 "~/.zcode/skills/$(basename "$d") shadows/duplicates the shared root (auto-fixable)"
    c3_bad=$((c3_bad + 1))
  done
fi
if [ "$c3_bad" -eq 0 ]; then result PASS c3 "~/.zcode/skills clean"; fi

# ---- C4: repo <-> node set parity + content drift vs baselines -----------------
c4_bad=0
only_node="$(comm -23 <(printf '%s\n' "$node_names") <(printf '%s\n' "$repo_names"))"
only_repo="$(comm -13 <(printf '%s\n' "$node_names") <(printf '%s\n' "$repo_names"))"
for n in $only_node; do
  result WARN c4 "node-only skill '$n' (harvest via adopt, or remove)"
  c4_bad=$((c4_bad + 1))
done
for n in $only_repo; do
  result ERROR c4 "repo skill '$n' not deployed to node"
  printf '%s\n' "$n" >> "$missing"
  c4_bad=$((c4_bad + 1))
done
while IFS=$'\t' read -r sec name hash; do
  [ -n "$hash" ] || continue
  [ -d "$NODE_SKILLS/$name" ] || continue
  if [ "$(hash_dir "$NODE_SKILLS/$name")" != "$hash" ]; then
    result ERROR c4 "$name content drifts from deployed baseline (adopt or restore)"
    c4_bad=$((c4_bad + 1))
  fi
done < "$baselines"
if [ "$c4_bad" -eq 0 ]; then result PASS c4 "repo<->node parity + zero content drift"; fi

# ---- C5: lock consistency (entries -> dirs; commit anchors; strays) ------------
c5_bad=0
while IFS=$'\t' read -r name sid commit; do
  if [ "$sid" = "<inHouse>" ]; then
    if [ ! -f "$INHOUSE/$name/SKILL.md" ]; then
      result WARN c5 "lock inHouse entry '$name' has no repo dir (stale baseline — remove entry)"
      c5_bad=$((c5_bad + 1))
    fi
    continue
  fi
  if [ ! -f "$VENDOR/$sid/$name/SKILL.md" ]; then
    result ERROR c5 "lock entry '$name' -> missing vendor/$sid/$name"
    c5_bad=$((c5_bad + 1))
  fi
  if [ -z "$commit" ]; then
    result WARN c5 "lock entry '$name' has no commit anchor"
    c5_bad=$((c5_bad + 1))
  fi
done < "$locksources"
# strays: vendor/github.com dirs that are neither lock entries nor frozen-registered
while IFS=$'\t' read -r zone src name; do
  [ "$zone" = vendor ] || continue
  case "$src" in "$UNKNOWN"/*) continue ;; esac
  printf '%s\n' "$repo_names" | grep -qxF "$name" || continue
  if ! awk -F'\t' '$1==n {found=1} END{exit !found}' n="$name" "$locksources"; then
    srcdir="${src%/}"                      # glob leaves a trailing slash
    sid="github.com/$(basename "$(dirname "$(dirname "$srcdir")")")/$(basename "$(dirname "$srcdir")")"
    frozen="$(python3 - "$LOCK" "$sid" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
e = d.get("sources", {}).get(sys.argv[2], {})
print("1" if e.get("frozen") else "0")
PY
)"
    if [ "$frozen" = "1" ]; then continue; fi
    if [ -f "$(dirname "$srcdir")/FROZEN.md" ]; then continue; fi
    result WARN c5 "stray vendor dir: $sid/$name (not a lock entry, not frozen-registered)"
    c5_bad=$((c5_bad + 1))
  fi
done < "$plan"
if [ "$c5_bad" -eq 0 ]; then result PASS c5 "lock entries <-> vendor dirs consistent, no strays"; fi

# ---- C6: node stray entries ----------------------------------------------------
c6_bad=0
for d in "$NODE_SKILLS"/*/; do
  [ -d "$d" ] || continue
  if [ ! -f "$d/SKILL.md" ]; then
    result ERROR c6 "stray dir in node skills root: $(basename "$d") (no SKILL.md)"
    c6_bad=$((c6_bad + 1))
  fi
done
for f in "$NODE_SKILLS"/*; do
  if [ -f "$f" ]; then
    result ERROR c6 "stray file in node skills root: $(basename "$f")"
    c6_bad=$((c6_bad + 1))
  fi
done
if [ "$c6_bad" -eq 0 ]; then result PASS c6 "node skills root clean"; fi

# ---- C7: harness expectations (config existence; --live handshake; expiry) -----
c7_bad=0
if [ "$LIVE" -eq 1 ]; then
  for ef in "$HARNESS"/*/expected.json; do
    [ -f "$ef" ] || continue
    hname="$(basename "$(dirname "$ef")")"
    python3 - "$ef" <<'PY' > "$HARNESS_EVAL"
import json, os, sys, datetime
e = json.load(open(sys.argv[1]))
def xp(p):
    return os.path.expanduser(p) if p else ""
va = e.get("verifiedAt", "")
expired = False
if va:
    d0 = datetime.date.fromisoformat(va)
    expired = (datetime.date.today() - d0).days > 90
print("VERIFIED_AT\t" + va)
print("EXPIRED\t" + ("1" if expired else "0"))
for u in e.get("unverified", []):
    print("UNVERIFIED\t" + u)
m = e.get("mcp") or {}
cp = xp(m.get("configPath"))
if cp and "mcp.configPath" not in e.get("unverified", []):
    print("MCP_PATH\t" + cp)
print("HANDSHAKE\t" + (m.get("handshake") or ""))
ad = xp(e.get("agentsDir"))
if ad:
    print("AGENTS_DIR\t" + ad + "\t" + str(e.get("agentsCount", 0)))
PY
    verified_line="$(grep '^VERIFIED_AT' "$HARNESS_EVAL" | cut -f2)"
    if [ "$(grep -c '^EXPIRED	1' "$HARNESS_EVAL" || true)" -gt 0 ]; then
      result WARN c7 "$hname: mechanism notes older than 90 days (verified $verified_line) — re-verify"
      c7_bad=$((c7_bad + 1))
    fi
    while IFS=$'\t' read -r kind val; do
      case "$kind" in
        UNVERIFIED) result UNVERIFIED c7 "$hname: $val (session verification pending — not counted)" ;;
        MCP_PATH)
          if [ ! -f "$val" ]; then
            result ERROR c7 "$hname: mcp config missing at verified path $val"
            c7_bad=$((c7_bad + 1))
          fi ;;
        HANDSHAKE)
          if [ "$val" = http ]; then
            code="$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://localhost:8228/mcp || true)"
            if [ "$code" = "000" ]; then
              result ERROR c7 "$hname: sideshow http endpoint dead (start via sync-mcps.sh)"
              c7_bad=$((c7_bad + 1))
            else
              log "INFO   [c7] $hname: sideshow http alive (HTTP $code)"
            fi
          else
            log "INFO   [c7] $hname: stdio handshake deferred to session verification"
          fi ;;
        AGENTS_DIR)
          adir="${val%	*}"; acount="${val##*	}"
          if [ ! -d "$adir" ]; then
            result ERROR c7 "$hname: agents dir missing: $adir"
            c7_bad=$((c7_bad + 1))
          else
            actual="$(ls "$adir" | wc -l | tr -d ' ')"
            if [ "$actual" != "$acount" ]; then
              result ERROR c7 "$hname: agents count $actual != expected $acount (fix: sync-agents.sh deploy)"
              c7_bad=$((c7_bad + 1))
            fi
          fi ;;
      esac
    done < "$HARNESS_EVAL"
  done
  # credential scan over collected configs
  for f in "$HARNESS"/*/config/*; do
    [ -f "$f" ] || continue
    if grep -qEi '"(env|headers)"[[:space:]]*:|token|secret|apikey|api_key|password' "$f"; then
      result WARN c7 "collected config looks credential-bearing: $f (redact and re-collect)"
      c7_bad=$((c7_bad + 1))
    fi
  done
  if [ "$c7_bad" -eq 0 ]; then result PASS c7 "harness expectations hold (--live)"; fi
else
  result INFO c7 "skipped (run with --live for harness expectations + MCP handshake)"
fi

# ---- --fix (whitelist: C3 symlinks, C1 in-house frontmatter, C2/C4 redeploy) ---
if [ "$FIX" -eq 1 ]; then
  if [ "$c3_bad" -gt 0 ]; then
    find "$ZCODE_SKILLS" -maxdepth 1 -type l -delete 2>/dev/null || true
    log "FIXED  [c3] removed shadowing entries in ~/.zcode/skills"
  fi
  if [ -n "$c1_fixable" ]; then
    for item in $c1_fixable; do
      f="${item%:*}"; name="${item##*:}"
      python3 - "$f" "$name" <<'PY'
import re, sys
p, name = sys.argv[1], sys.argv[2]
s = open(p).read()
s = re.sub(r"^name:[ \t]*.*$", f"name: {name}", s, count=1, flags=re.M)
open(p, "w").write(s)
PY
      log "FIXED  [c1] $name: frontmatter name -> dirname"
    done
  fi
  if [ -s "$missing" ]; then
    log "INFO   [--fix] redeploying missing skills (delta-guarded): $(tr '\n' ' ' < "$missing")"
    "$REPO_ROOT/hack/sync-skills.sh" restore $(tr '\n' ' ' < "$missing") || \
      log "WARN   [--fix] redeploy blocked by delta guard — review drift, then adopt or restore --force"
  fi
fi

log "----------------------------------------"
log "doctor v1: $err error(s), $warnn warning(s), $unv unverified$( [ "$LIVE" -eq 1 ] && echo ' (--live)' || echo ' (static; --live for C7)')"
exit "$err"
