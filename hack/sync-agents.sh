#!/usr/bin/env bash
# sync-agents.sh — keep subagent definitions in sync between this repo's
# canonical agents/ store and every agent harness installed on this node.
#
# Canonical format (repo agents/ and ~/.zcode/agents):
#   ---
#   name: my-agent
#   description: one-line dispatch description
#   tools: [Read, Grep, Glob]
#   ---
#   <system prompt body>
#
# Usage: hack/sync-agents.sh [collect|deploy [harness...]|list]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_AGENTS="$REPO_ROOT/agents"
NODE_ZCODE_AGENTS="${ZCODE_AGENTS_DIR:-$HOME/.zcode/agents}"

# harness:target_dir:tools_format   (format: array keeps [..]; comma flattens to CSV)
HARNESSES=(
  "zcode:${ZCODE_AGENTS_DIR:-$HOME/.zcode/agents}:array"
  "claude:${CLAUDE_AGENTS_DIR:-$HOME/.claude/agents}:comma"
  "antigravity:${ANTIGRAVITY_AGENTS_DIR:-$HOME/.gemini/config/agents}:array"
  "deepseek:${DEEPSEEK_AGENTS_DIR:-$HOME/.deepseek/agents}:comma"
)

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

fm_of()  { awk 'NR==1&&$0~/^---[[:space:]]*$/{infm=1;next} infm&&$0~/^---[[:space:]]*$/{exit} infm{print}' "$1"; }
body_of() { awk 'NR==1&&$0~/^---[[:space:]]*$/{infm=1;next} infm&&$0~/^---[[:space:]]*$/{infm=0;body=1;next} body{print}' "$1"; }
fm_val() { sed -n "s/^$1:[[:space:]]*//p" | head -1; }   # reads stdin

tools_csv() { sed -e 's/[][]//g' -e 's/[[:space:]]//g' <<< "$1"; }

emit_agent() { # $1=dest file  $2=name  $3=description  $4=tools-array  $5=body  $6=format
  {
    echo "---"
    echo "name: $2"
    echo "description: $3"
    if [ "$6" = comma ]; then
      echo "tools: $(tools_csv "$4")"
    else
      echo "tools: $4"
    fi
    echo "---"
    echo "$5"
  } > "$1"
}

# collect — mirror node ~/.zcode/agents/*.md into the repo store (canonical).
cmd_collect() {
  local f name count=0
  mkdir -p "$REPO_AGENTS"
  for f in "$NODE_ZCODE_AGENTS"/*.md; do
    [ -f "$f" ] || continue
    name="$(fm_of "$f" | fm_val name)"
    [ -n "$name" ] || continue
    cp "$f" "$REPO_AGENTS/$name.md"
    log "collected: $name"
    count=$((count + 1))
  done
  log "collected $count agents into $REPO_AGENTS"
}

# deploy [harness...] — write repo agents/ into each harness's agents dir,
# converting tools frontmatter per harness (additive, never deletes).
cmd_deploy() {
  local selected=("$@")
  [ ${#selected[@]} -eq 0 ] && selected=(all)
  local f name desc tools body spec h dir fmt convert_all
  for spec_select in "${selected[@]}"; do
    for spec in "${HARNESSES[@]}"; do
      h="${spec%%:*}"; rest="${spec#*:}"; dir="${rest%%:*}"; fmt="${rest##*:}"
      [ "$spec_select" = all ] || [ "$spec_select" = "$h" ] || continue
      mkdir -p "$dir"
      convert_all=0
      for f in "$REPO_AGENTS"/*.md; do
        [ -f "$f" ] || continue
        name="$(fm_of "$f" | fm_val name)"; [ -n "$name" ] || continue
        desc="$(fm_of "$f" | fm_val description)"
        tools="$(fm_of "$f" | fm_val tools)"
        body="$(body_of "$f")"
        emit_agent "$dir/$name.md" "$name" "$desc" "$tools" "$body" "$fmt"
        convert_all=$((convert_all + 1))
      done
      log "$h: deployed $convert_all agents -> $dir"
    done
  done
}

# list — repo agents and deployment status per harness.
cmd_list() {
  local f name spec h dir
  for f in "$REPO_AGENTS"/*.md; do
    [ -f "$f" ] || continue
    name="$(fm_of "$f" | fm_val name)"; name="${name:-$(basename "$f" .md)}"
    status=""
    for spec in "${HARNESSES[@]}"; do
      h="${spec%%:*}"; dir="${spec#*:}"; dir="${dir%%:*}"
      [ -f "$dir/$name.md" ] && status="$status $h=✓" || status="$status $h=–"
    done
    printf '%-32s %s\n' "$name" "$status"
  done | sort
}

usage() {
  cat <<EOF
usage: hack/sync-agents.sh [command]

commands:
  collect            mirror node ~/.zcode/agents -> repo agents/ (canonical)
  deploy [harness]   repo agents/ -> harness dirs (default: all)
                     harnesses: zcode claude antigravity deepseek
  list               repo agents + per-harness deployment status

agent definitions live in agents/ as markdown with name/description/tools
frontmatter plus the system-prompt body. harness dirs are overridable via
env: ZCODE_AGENTS_DIR, CLAUDE_AGENTS_DIR, ANTIGRAVITY_AGENTS_DIR,
DEEPSEEK_AGENTS_DIR.
EOF
}

case "${1:-list}" in
  collect) cmd_collect ;;
  deploy)  shift; cmd_deploy "$@" ;;
  list)    cmd_list ;;
  -h|--help|help) usage ;;
  *) usage; die "unknown command: $1" ;;
esac
