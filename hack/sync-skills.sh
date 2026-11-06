#!/usr/bin/env bash
# sync-skills.sh — keep agent skills in sync between remote git sources,
# this node (~/.agents/skills + ~/.zcode/skills), and this backup repo.
#
# Layout conventions on this node:
#   ~/.agents/skills/<name>   real skill directories (shared across tools)
#   ~/.zcode/skills/<name>    symlink -> ../../.agents/skills/<name>
#   <repo>/skills/<name>      this repo's backup of the node's skills
#
# Usage: hack/sync-skills.sh [pull|backup|snapshot|restore|list]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_SKILLS="$REPO_ROOT/skills"
NODE_SKILLS="$HOME/.agents/skills"
ZCODE_SKILLS="$HOME/.zcode/skills"
ZCODE_AGENTS="$HOME/.zcode/agents"
SOURCES_CONF="$REPO_ROOT/hack/sources.conf"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

ensure_dir_links() {
  mkdir -p "$NODE_SKILLS" "$ZCODE_SKILLS"
  local d name
  for d in "$NODE_SKILLS"/*/; do
    [ -f "$d/SKILL.md" ] || continue
    name="$(basename "$d")"
    ln -sfn "../../.agents/skills/$name" "$ZCODE_SKILLS/$name"
  done
}

# pull — clone every source in sources.conf, refresh the node's installed
# skills from it, and mirror each installed skill into this repo.
# subdir may be comma-separated; SKILL.md dirs are found at any depth <= 4.
cmd_pull() {
  [ -r "$SOURCES_CONF" ] || die "missing $SOURCES_CONF"
  local workdir url subdir shared src s d name sub
  workdir="$(mktemp -d "${TMPDIR:-/tmp}/skill-sources.XXXXXX")"
  while IFS='|' read -r url subdir shared; do
    case "$url" in ''|'#'*) continue ;; esac
    url="$(trim "$url")"; subdir="$(trim "$subdir")"; shared="$(trim "$shared")"
    log "source: $url"
    src="$workdir/$(basename "$url" .git)"
    git clone --quiet --depth 1 "$url" "$src" || die "clone failed: $url"
    IFS=',' read -r -a subdirs <<< "${subdir:-.}"
    for sub in "${subdirs[@]}"; do
      sub="$(trim "$sub")"
      [ -n "$sub" ] || continue
      [ -d "$src/$sub" ] || { warn "no $sub/ in $url"; continue; }
      while IFS= read -r skillmd; do
        d="$(dirname "$skillmd")"
        name="$(basename "$d")"
        rsync -a --delete "$d/" "$NODE_SKILLS/$name/"
        # shared plugin-root trees (e.g. egm agents/, resources/, docs/)
        IFS=',' read -r -a shared_dirs <<< "${shared:-}"
        for s in ${shared_dirs[@]+"${shared_dirs[@]}"}; do
          s="$(trim "$s")"
          [ -n "$s" ] || continue
          if [ -d "$src/$s" ]; then
            rsync -a --delete "$src/$s/" "$NODE_SKILLS/$name/$s/"
          else
            warn "shared dir '$s' not found in $url"
          fi
        done
        rsync -a --delete "$NODE_SKILLS/$name/" "$BACKUP_SKILLS/$name/"
        log "  installed + backed up: $name"
      done < <(find "$src/$sub" -maxdepth 4 -name SKILL.md -not -path '*/node_modules/*' | sort)
    done
  done < "$SOURCES_CONF"
  rm -rf "$workdir"
  ensure_dir_links
  cmd_agents
  log "pull complete"
}

# backup — copy every node skill into this repo (additive, never deletes).
cmd_backup() {
  local d name
  mkdir -p "$BACKUP_SKILLS"
  for d in "$NODE_SKILLS"/*/; do
    [ -f "$d/SKILL.md" ] || continue
    name="$(basename "$d")"
    rsync -a "$d/" "$BACKUP_SKILLS/$name/"
  done
  log "node skills backed up to skills/ (additive)"
}

# snapshot — backup, then git commit the result.
cmd_snapshot() {
  cmd_backup
  ensure_dir_links
  cd "$REPO_ROOT"
  git add -A
  if git diff --cached --quiet; then
    log "nothing to commit"
  else
    git commit -m "sync: node skills snapshot $(date +%Y-%m-%d)"
    log "committed. push with: git -C $REPO_ROOT push"
  fi
}

# restore [skill...] — copy skills from this repo back onto the node
# (exact mirror with --delete) and recreate ~/.zcode/skills symlinks.
cmd_restore() {
  local d name
  if [ "$#" -gt 0 ]; then
    for name in "$@"; do
      [ -f "$BACKUP_SKILLS/$name/SKILL.md" ] || die "no skill '$name' in $BACKUP_SKILLS"
      rsync -a --delete "$BACKUP_SKILLS/$name/" "$NODE_SKILLS/$name/"
      log "restored: $name"
    done
  else
    for d in "$BACKUP_SKILLS"/*/; do
      [ -f "$d/SKILL.md" ] || continue
      name="$(basename "$d")"
      rsync -a --delete "$d/" "$NODE_SKILLS/$name/"
    done
    log "restored all skills from backup repo"
  fi
  ensure_dir_links
  cmd_agents
}

# agents — generate user-scope ZCode subagent definitions from every installed
# skill's agents/*.md persona files. Persona body is embedded verbatim; the
# skill copy stays the single source of truth, so re-run after pulls.
agent_tools() { # $1=agent name -> ZCode tools allowlist
  case "$1" in
    egm-synthesizer)            echo "[Read, Grep, Glob, Write, Agent]" ;;
    egm-bootstrap-orchestrator) echo "[Read, Grep, Glob, Write, Edit, Agent]" ;;
    *)                          echo "[Read, Grep, Glob]" ;;  # reviewers: read-only
  esac
}

cmd_agents() {
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
      log "agent: $name <- $(basename "$d")"
      count=$((count + 1))
    done
  done
  log "generated $count agent definitions in $ZCODE_AGENTS"
  # refresh the repo's canonical store and deploy to every harness
  if [ -x "$REPO_ROOT/hack/sync-agents.sh" ]; then
    "$REPO_ROOT/hack/sync-agents.sh" collect
    "$REPO_ROOT/hack/sync-agents.sh" deploy all
  fi
}

# list — installed node skills, marked [link] when the ~/.zcode symlink exists.
cmd_list() {
  local d name
  for d in "$NODE_SKILLS"/*/; do
    [ -f "$d/SKILL.md" ] || continue
    name="$(basename "$d")"
    [ -L "$ZCODE_SKILLS/$name" ] && mark="[link]" || mark="[----]"
    printf '%-7s %s\n' "$mark" "$name"
  done | sort -k2
}

trim() {
  local s="$*"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

usage() {
  cat <<EOF
usage: hack/sync-skills.sh [command]

commands:
  pull              install/refresh skills from sources in hack/sources.conf
                    onto this node and mirror them into this repo
  backup            copy node skills -> this repo (additive)
  snapshot          backup + git commit
  restore [name...] restore skills from this repo -> node (default: all)
  agents            regenerate ~/.zcode/agents subagent definitions from
                    every installed skill's agents/*.md persona files
  list              list installed node skills
EOF
}

case "${1:-pull}" in
  pull)     cmd_pull ;;
  backup)   cmd_backup ;;
  snapshot) cmd_snapshot ;;
  restore)  shift; cmd_restore "$@" ;;
  agents)   cmd_agents ;;
  list)     cmd_list ;;
  -h|--help|help) usage ;;
  *) usage; die "unknown command: $1" ;;
esac
