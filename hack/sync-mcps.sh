#!/usr/bin/env bash
# sync-mcps.sh — run MCP services in the background on this node and wire
# them into every agent harness. Definitions live in mcps/*.json:
#
# {
#   "name": "sideshow",
#   "repo": "git@github.com:modem-dev/sideshow.git",
#   "workdir": "~/code/github.com/modem-dev/sideshow",
#   "install": "npm install --no-fund --no-audit",
#   "service": { "command": "npm", "args": ["run", "start"], "port": 8228 },
#   "http":    { "url": "http://localhost:8228/mcp" },
#   "stdio":   { "command": "npm", "args": ["run", "mcp"] }
# }
#
# "service" is the background process managed by start/stop/status.
# "http"/"stdio" are the harness-facing MCP entries: configure writes the
# http entry for harnesses listed in HTTP_HARNESSES and the stdio entry
# (self-spawned per conversation) for the rest.
#
# Usage: hack/sync-mcps.sh [sync|start|stop|status|configure] [name...]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MCPS_DIR="$REPO_ROOT/mcps"
RUN_DIR="${MCP_RUN_DIR:-$HOME/.node-mcps}"

HTTP_HARNESSES=" zcode "   # these get the http entry; others get stdio

# harness configs:  name:config_file:container_key
HARNESSES=(
  "zcode:${ZCODE_MCP_CONFIG:-$HOME/.zcode/cli/config.json}:mcp.servers"
  "claude:${CLAUDE_MCP_CONFIG:-$HOME/.claude.json}:mcpServers"
  "antigravity:${ANTIGRAVITY_MCP_CONFIG:-$HOME/.gemini/config/mcp.json}:mcpServers"
  "deepseek:${DEEPSEEK_MCP_CONFIG:-$HOME/.deepseek/mcp.json}:mcpServers"
)

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

defs()    { [ -d "$MCPS_DIR" ] && find "$MCPS_DIR" -maxdepth 1 -name '*.json' | sort || true; }
def_val() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); v=d; [v:=v.get(k,{}) for k in sys.argv[2].split(".")]; print(v if isinstance(v,(str,int,float)) else "")' "$1" "$2"; }
def_arr() { python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])).get(sys.argv[2],{}).get("args",[])))' "$1" "$2"; }
exp_path(){ python3 -c 'import os,sys; print(os.path.expanduser(sys.argv[1]))' "$1"; }
port_open(){ lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

pidfile() { echo "$RUN_DIR/$1.pid"; }
logfile() { echo "$RUN_DIR/$1.log"; }

# daemonize — launch fully detached (new session) so the server survives the
# calling shell; writes the detached pid to the pidfile.
daemonize() { # $1=workdir $2=pidfile $3=logfile $4=command $5=args-json
  local wd="$1" pidf="$2" logf="$3" cmd="$4" args="$5"
  PID_OUT="$pidf" WD="$wd" LOGF="$logf" DAEMON_CMD="$cmd" DAEMON_ARGS="$args" \
  python3 <<'PY'
import json, os, subprocess
out = open(os.environ["LOGF"], "ab")
argv = [os.environ["DAEMON_CMD"]] + json.loads(os.environ["DAEMON_ARGS"] or "[]")
p = subprocess.Popen(
    argv, cwd=os.environ["WD"], stdin=subprocess.DEVNULL,
    stdout=out, stderr=subprocess.STDOUT, start_new_session=True)
with open(os.environ["PID_OUT"], "w") as fh:
    fh.write(str(p.pid))
print(p.pid)
PY
}

# sync — clone or fast-forward each MCP's repo, then run its install step.
cmd_sync() {
  local f name wd install
  for f in $(select_defs "$@"); do
    name="$(def_val "$f" name)"
    wd="$(exp_path "$(def_val "$f" workdir)")"
    log "sync: $name"
    if [ -d "$wd/.git" ]; then
      if [ -n "$(git -C "$wd" status --porcelain | head -1)" ]; then
        warn "  $wd has local changes; skipping pull (run manually)"
      else
        git -C "$wd" pull --ff-only --quiet || warn "  pull failed for $wd"
      fi
    else
      mkdir -p "$(dirname "$wd")"
      git clone --quiet "$(def_val "$f" repo)" "$wd" || die "clone failed: $(def_val "$f" repo)"
    fi
    install="$(def_val "$f" install)"
    if [ -n "$install" ] && [ -f "$wd/package.json" ]; then
      (cd "$wd" && eval "$install") || warn "  install failed for $name"
    fi
  done
}

# start — launch the service fully detached, wait for its port to open.
cmd_start() {
  local f name wd port pid i
  mkdir -p "$RUN_DIR"
  for f in $(select_defs "$@"); do
    name="$(def_val "$f" name)"
    wd="$(exp_path "$(def_val "$f" workdir)")"
    port="$(def_val "$f" service.port)"
    [ -d "$wd" ] || die "$name: no workdir $wd (run 'sync-mcps.sh sync' first)"
    if port_open "$port"; then
      log "start: $name already listening on :$port"
      continue
    fi
    log "start: $name"
    : > "$(logfile "$name")"
    daemonize "$wd" "$(pidfile "$name")" "$(logfile "$name")" \
      "$(def_val "$f" service.command)" "$(def_arr "$f" service)"
    for i in $(seq 1 120); do   # up to 60s: service may build first
      port_open "$port" && break
      kill -0 "$(cat "$(pidfile "$name")")" 2>/dev/null || break
      sleep 0.5
    done
    pid="$(cat "$(pidfile "$name")")"
    if port_open "$port"; then
      log "  $name up on :$port (pid $pid, log $(logfile "$name"))"
    else
      warn "  $name not listening on :$port yet (pid $pid, log $(logfile "$name"))"
    fi
  done
}

# stop — terminate the service pid + children, fall back to freeing the port.
cmd_stop() {
  local f name port pid
  for f in $(select_defs "$@"); do
    name="$(def_val "$f" name)"
    port="$(def_val "$f" service.port)"
    log "stop: $name"
    if [ -f "$(pidfile "$name")" ]; then
      pid="$(cat "$(pidfile "$name")")"
      pkill -TERM -P "$pid" 2>/dev/null || true
      kill -TERM "$pid" 2>/dev/null || true
      for i in 1 2 3 4 5 6; do port_open "$port" 2>/dev/null || break; sleep 1; done
      kill -KILL "$pid" 2>/dev/null || true
      rm -f "$(pidfile "$name")"
    fi
    if [ -n "$port" ] && port_open "$port" 2>/dev/null; then
      lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | xargs kill 2>/dev/null || true
      sleep 1
    fi
    if [ -n "$port" ] && port_open "$port" 2>/dev/null; then
      warn "  :$port still listening"
    else
      log "  $name stopped"
    fi
  done
}

# status — one line per MCP: pid + port state.
cmd_status() {
  local f name port pid state
  for f in $(select_defs "$@"); do
    name="$(def_val "$f" name)"
    port="$(def_val "$f" service.port)"
    state="stopped"
    if [ -f "$(pidfile "$name")" ]; then
      pid="$(cat "$(pidfile "$name")")"
      kill -0 "$pid" 2>/dev/null && state="pid $pid" || state="stale pid $pid"
    fi
    if [ -n "$port" ] && port_open "$port"; then
      state="$state, listening :$port"
    else
      state="$state, not listening :$port"
    fi
    printf '%-16s %s\n' "$name" "$state"
  done
}

# configure [harness...] — merge MCP entries into harness configs (idempotent).
cmd_configure() {
  local selected=("$@")
  [ ${#selected[@]} -eq 0 ] && selected=(all)
  local f name spec h file key
  for f in $(defs); do
    name="$(def_val "$f" name)"
    for spec in "${HARNESSES[@]}"; do
      h="${spec%%:*}"; rest="${spec#*:}"; file="${rest%%:*}"; key="${rest##*:}"
      matched=0
      for s in "${selected[@]}"; do [ "$s" = all ] || [ "$s" = "$h" ] && matched=1; done
      [ "$matched" = 1 ] || continue
      if [[ "$HTTP_HARNESSES" == *" $h "* ]]; then
        entry_type="http"; url="$(def_val "$f" http.url)"; mcmd=""; margs="[]"
      else
        entry_type="stdio"; url=""
        mcmd="$(def_val "$f" stdio.command)"; margs="$(def_arr "$f" stdio)"
      fi
      MCP_FILE="$file" MCP_KEY="$key" MCP_NAME="$name" \
      MCP_ENTRY_TYPE="$entry_type" MCP_URL="$url" \
      MCP_CMD="$mcmd" MCP_ARGS="$margs" \
      python3 <<'PY'
import json, os
path, key, name = os.environ["MCP_FILE"], os.environ["MCP_KEY"], os.environ["MCP_NAME"]
data = {}
if os.path.exists(path):
    with open(path) as fh:
        data = json.load(fh)
node = data
for p in key.split("."):
    node = node.setdefault(p, {})
if os.environ["MCP_ENTRY_TYPE"] == "http":
    node[name] = {"type": "http", "url": os.environ["MCP_URL"]}
else:
    node[name] = {"type": "stdio", "command": os.environ["MCP_CMD"],
                  "args": json.loads(os.environ["MCP_ARGS"])}
os.makedirs(os.path.dirname(os.path.expanduser(path)), exist_ok=True)
with open(os.path.expanduser(path), "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
print(f"configured: {name} ({os.environ['MCP_ENTRY_TYPE']}) -> {path} ({key})")
PY
    done
  done
}

select_defs() { # all defs, or only those matching names given as args
  local f name want="$*"
  for f in $(defs); do
    if [ -n "$want" ]; then
      name="$(def_val "$f" name)"
      case " $want " in *" $name "*) ;; *) continue ;; esac
    fi
    echo "$f"
  done
}

usage() {
  cat <<EOF
usage: hack/sync-mcps.sh [command] [name...]

commands:
  sync             clone/fast-forward repos + install deps
  start            launch services in background (pid+log in ~/.node-mcps)
  stop             terminate services
  status           pid / port state per service
  configure [h]    merge entries into harness configs (default all:
                   zcode claude antigravity deepseek; zcode gets the http
                   entry, others the stdio entry)
EOF
}

case "${1:-status}" in
  sync)      shift; cmd_sync "$@" ;;
  start)     shift; cmd_start "$@" ;;
  stop)      shift; cmd_stop "$@" ;;
  status)    shift; cmd_status "$@" ;;
  configure) shift; cmd_configure "$@" ;;
  -h|--help|help) usage ;;
  *) usage; die "unknown command: $1" ;;
esac
