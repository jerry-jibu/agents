#!/usr/bin/env bash
# doctor.sh — expectation-vs-reality health checks for the agent-skills repo.
#
# v0 (Stage 1): static subset C1-C4 + C6 with hardcoded expectations.
# Stage 2 adds: C5 (lock consistency), C7 (--live MCP handshake + expected.json
# consumption + verifiedAt expiry), --fix whitelist expansion.
#
# Zones: in-house/skills (self-authored) | vendor/github.com/<o>/<r>/<name>
# (live mirror, lock-tracked) | vendor/unknown (frozen, not in lock).
# Exit code: number of ERROR findings (0 = green).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$REPO_ROOT/vendor"
UNKNOWN="$VENDOR/unknown"
INHOUSE="$REPO_ROOT/in-house/skills"
NODE_SKILLS="$HOME/.agents/skills"
ZCODE_SKILLS="$HOME/.zcode/skills"
LOCK="$REPO_ROOT/.skill-lock.json"

log()  { printf '%s\n' "$*"; }
err=0; warnn=0

# check registry: parallel arrays (bash 3.2 — no associative arrays)
CHECK_IDS=(c1 c2 c3 c4 c6)
CHECK_SEV=(mixed error error error error)
CHECK_DESC=("frontmatter name/depends-on" "depends-on targets exist+deployed" "zcode skills dedup" "repo<->node set+content" "node stray dirs")

# deployedHash algorithm — shared with sync-skills.sh (design: 共用函数)
source "$REPO_ROOT/hack/lib-hash.sh"

result() { # $1=level $2=check $3=message
  case "$1" in
    ERROR) log "ERROR  [$2] $3"; err=$((err + 1)) ;;
    WARN)  log "WARN   [$2] $3"; warnn=$((warnn + 1)) ;;
    PASS)  log "PASS   [$2] $3" ;;
    *)     log "INFO   [$2] $3" ;;
  esac
}

# repo deploy set: "zone<TAB>srcdir<TAB>name"
plan="$(mktemp "${TMPDIR:-/tmp}/doctor.plan.XXXXXX")"
trap 'rm -f "$plan" "$baselines" "$locksources"' EXIT
baselines="$(mktemp "${TMPDIR:-/tmp}/doctor.base.XXXXXX")"
locksources="$(mktemp "${TMPDIR:-/tmp}/doctor.src.XXXXXX")"
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
    print(f"{name}\t{e.get('source','')}")
PY

shopt -s nullglob
for d in "$VENDOR"/github.com/*/*/*/; do
  [ -f "$d/SKILL.md" ] && printf 'vendor\t%s\t%s\n' "$d" "$(basename "$d")" >> "$plan" || true
done
for d in "$UNKNOWN"/*/; do
  [ -f "$d/SKILL.md" ] && printf 'vendor\t%s\t%s\n' "$d" "$(basename "$d")" >> "$plan" || true
done
for d in "$INHOUSE"/*/; do
  [ -f "$d/SKILL.md" ] && printf 'inhouse\t%s\t%s\n' "$d" "$(basename "$d")" >> "$plan" || true
done
shopt -u nullglob

repo_names="$(awk -F'\t' '{print $3}' "$plan" | sort)"
node_names="$(ls "$NODE_SKILLS" 2>/dev/null | sort)"

# ---- C1: frontmatter (name == dirname; depends-on key present is optional,
#          its FORMAT is checked; in-house=error, vendor/unknown=warn) --------
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
      result ERROR c1 "$name: frontmatter name '$fmname' != dirname (auto-fixable: hack/doctor.sh --fix)"
    else
      result WARN c1 "$name: frontmatter name '$fmname' != dirname (mirror/frozen content — report upstream, never hand-edit)"
    fi
    c1_bad=$((c1_bad + 1))
  fi
done < "$plan"
[ "$c1_bad" -eq 0 ] && result PASS c1 "frontmatter ok for $(awk -F'\t' '{print $3}' "$plan" | wc -l | tr -d ' ') skills"

# ---- C2: depends-on targets exist (in-house|vendor) and are deployed -------
c2_bad=0
deps_all="$(mktemp "${TMPDIR:-/tmp}/doctor.deps.XXXXXX")"
trap 'rm -f "$plan" "$baselines" "$locksources" "$deps_all"' EXIT
while IFS=$'\t' read -r zone src name; do
  dep="$(sed -n 's/^depends-on:[[:space:]]*//p' "$src/SKILL.md" | head -1)"
  [ -n "$dep" ] || continue
  IFS=',' read -r -a deps <<< "$(printf '%s' "$dep" | tr -d ' ')"
  for depname in ${deps[@]+"${deps[@]}"}; do
    printf '%s\t%s\t%s\n' "$name" "$depname" "$zone" >> "$deps_all"
  done
done < "$plan"
while IFS=$'\t' read -r from dep zone; do
  if ! printf '%s\n' "$repo_names" | grep -qxF "$dep"; then
    result ERROR c2 "$from depends-on '$dep': not found in any repo zone"
    c2_bad=$((c2_bad + 1))
  elif ! [ -d "$NODE_SKILLS/$dep" ]; then
    result ERROR c2 "$from depends-on '$dep': exists in repo but NOT deployed to node (fix: hack/sync-skills.sh restore $dep)"
    c2_bad=$((c2_bad + 1))
  fi
done < "$deps_all"
[ "$c2_bad" -eq 0 ] && result PASS c2 "all depends-on targets exist and are deployed"

# ---- C3: ~/.zcode/skills must not shadow ~/.agents/skills (default: empty) --
c3_bad=0
if [ -d "$ZCODE_SKILLS" ]; then
  for d in "$ZCODE_SKILLS"/*; do
    [ -e "$d" ] || continue
    n="$(basename "$d")"
    result ERROR c3 "~/.zcode/skills/$n shadows/duplicates node skills root (fix: delete the symlink)"
    c3_bad=$((c3_bad + 1))
  done
fi
[ "$c3_bad" -eq 0 ] && result PASS c3 "~/.zcode/skills clean (no shadowing entries)"

# ---- C4: repo <-> node set parity + content drift vs deployed baselines -----
c4_bad=0
only_node="$(comm -23 <(printf '%s\n' "$node_names") <(printf '%s\n' "$repo_names"))"
only_repo="$(comm -13 <(printf '%s\n' "$node_names") <(printf '%s\n' "$repo_names"))"
for n in $only_node; do
  result WARN c4 "node-only skill '$n' (not in any repo zone — harvest via adopt or remove)"
  c4_bad=$((c4_bad + 1))
done
for n in $only_repo; do
  result ERROR c4 "repo skill '$n' not deployed to node (fix: hack/sync-skills.sh restore $n)"
  c4_bad=$((c4_bad + 1))
done
# content drift: every lock entry with a baseline must match node
while IFS=$'\t' read -r sec name hash; do
  [ -n "$hash" ] || continue
  [ -d "$NODE_SKILLS/$name" ] || continue
  if [ "$(hash_dir "$NODE_SKILLS/$name")" != "$hash" ]; then
    result ERROR c4 "$name content drifts from deployed baseline (adopt or restore)"
    c4_bad=$((c4_bad + 1))
  fi
done < "$baselines"
[ "$c4_bad" -eq 0 ] && result PASS c4 "repo<->node set parity + zero content drift"

# ---- C6: node stray dirs (non-skill entries in the shared root) --------------
c6_bad=0
for d in "$NODE_SKILLS"/*/; do
  [ -d "$d" ] || continue
  if [ ! -f "$d/SKILL.md" ]; then
    result ERROR c6 "stray dir in node skills root: $(basename "$d") (no SKILL.md — remove after review)"
    c6_bad=$((c6_bad + 1))
  fi
done
for f in "$NODE_SKILLS"/*; do
  [ -f "$f" ] || continue
  result ERROR c6 "stray file in node skills root: $(basename "$f")"
  c6_bad=$((c6_bad + 1))
done
[ "$c6_bad" -eq 0 ] && result PASS c6 "node skills root clean"

# ---- --fix (v0 whitelist: C3 symlink removal only) ----------------------------
if [ "${1:-}" = "--fix" ]; then
  if [ "$c3_bad" -gt 0 ]; then
    find "$ZCODE_SKILLS" -maxdepth 1 -type l -delete 2>/dev/null || true
    log "FIXED  [c3] removed shadowing entries in ~/.zcode/skills"
  fi
  log "INFO   [--fix] C1 in-house frontmatter / C2+C4 redeploy: run hack/sync-skills.sh restore (delta-guarded)"
fi

log "----------------------------------------"
log "doctor v0: $err error(s), $warnn warning(s) — checks: ${CHECK_IDS[*]}"
[ "${1:-}" = "--list" ] && {
  i=0
  for id in ${CHECK_IDS[@]+"${CHECK_IDS[@]}"}; do
    log "  $id  sev=${CHECK_SEV[$i]}  ${CHECK_DESC[$i]}"
    i=$((i + 1))
  done
}
exit "$err"
