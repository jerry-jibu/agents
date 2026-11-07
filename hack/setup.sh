#!/usr/bin/env bash
# setup.sh — new-machine bootstrap for the agent-skills environment.
#
# Levels (default 3; each level ends with a doctor gate):
#   L0  structure: repo zones present, lock v4 valid
#   L1  skills: materialize repo -> node (delta-guarded), doctor static green
#   L2  agents: deploy personas -> zcode/claude/antigravity, doctor agents green
#   L3  mcp: write harness configs, ensure sideshow service, doctor --live green
#
# Usage: hack/setup.sh [--level N]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEVEL=3
while [ "$#" -gt 0 ]; do
  case "$1" in
    --level) LEVEL="${2:?--level needs a number}"; shift ;;
    *) printf 'unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
gate() { # $1=label $2=doctor args...
  local label="$1"; shift
  log "gate[$label]: hack/doctor.sh $*"
  "$REPO_ROOT/hack/doctor.sh" "$@" > /tmp/doctor.gate.$$ 2>&1 || {
    cat /tmp/doctor.gate.$$ >&2
    rm -f /tmp/doctor.gate.$$
    die "gate[$label] failed"
  }
  rm -f /tmp/doctor.gate.$$
  log "gate[$label]: PASS"
}

[ "$LEVEL" -ge 0 ] && [ "$LEVEL" -le 3 ] 2>/dev/null || die "--level must be 0..3"

# ---- L0: structure --------------------------------------------------------------
log "L0: structure + lock"
for d in vendor/github.com in-house/skills harness agents mcps hack; do
  [ -d "$REPO_ROOT/$d" ] || die "L0: missing repo zone: $d"
done
[ -f "$REPO_ROOT/.skill-lock.json" ] || die "L0: missing .skill-lock.json"
python3 - "$REPO_ROOT/.skill-lock.json" <<'PY' || die "L0: lock v4 invalid"
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("version") == 4, "lock version != 4"
assert isinstance(d.get("sources"), dict) and d["sources"], "no sources registry"
assert isinstance(d.get("skills"), dict), "no skills section"
PY
log "L0: PASS ($(python3 -c "import json;print(len(json.load(open('$REPO_ROOT/.skill-lock.json'))['skills']))" 2>/dev/null || echo '?') lock entries)"
[ "$LEVEL" -eq 0 ] && exit 0

# ---- L1: skills ------------------------------------------------------------------
log "L1: materialize skills -> node (delta-guarded)"
"$REPO_ROOT/hack/sync-skills.sh" restore
gate L1 --fix

# ---- L2: agents ------------------------------------------------------------------
log "L2: deploy agents -> zcode/claude/antigravity"
"$REPO_ROOT/hack/sync-agents.sh" deploy
gate L2

# ---- L3: mcp ---------------------------------------------------------------------
log "L3: write harness MCP configs + ensure sideshow service"
"$REPO_ROOT/hack/sync-mcps.sh" configure || log "configure: partial (unverified harness paths pending — see harness/*/NOTES.md)"
if ! curl -s -m 2 -o /dev/null http://localhost:8228/mcp; then
  log "sideshow service down — starting"
  "$REPO_ROOT/hack/sync-mcps.sh" start
  sleep 2
fi
gate L3 --live

log "setup complete at level $LEVEL — doctor green."
