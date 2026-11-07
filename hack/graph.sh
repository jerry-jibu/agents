#!/usr/bin/env bash
# graph.sh — skill dependency graph from SKILL.md depends-on frontmatter
# (design Future Improvements: "depends-on 数据的副产品").
#
# Output: mermaid flowchart (skill --> dependency) + integrity report.
# Node classes: in-house (solid) vs vendor (dashed).
# Exits with the count of broken edges (depends-on -> nonexistent skill).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$REPO_ROOT/vendor"
UNKNOWN="$VENDOR/unknown"
INHOUSE="$REPO_ROOT/in-house/skills"
NODE_SKILLS="$HOME/.agents/skills"

edges="$(mktemp "${TMPDIR:-/tmp}/graph.edges.XXXXXX")"
nodes="$(mktemp "${TMPDIR:-/tmp}/graph.nodes.XXXXXX")"
trap 'rm -f "$edges" "$nodes"' EXIT
: > "$edges"; : > "$nodes"
broken=0
undeployed=0

zone_of() { # $1=name -> inhouse|vendor|missing
  if [ -d "$INHOUSE/$1" ]; then echo inhouse
  elif [ -d "$UNKNOWN/$1" ]; then echo vendor
  elif ls -d "$VENDOR"/github.com/*/*/"$1" >/dev/null 2>&1; then echo vendor
  else echo missing; fi
}

add_skill() { # $1=name $2=zone $3=srcdir
  printf '%s\t%s\n' "$1" "$2" >> "$nodes"
  local dep
  dep="$(sed -n 's/^depends-on:[[:space:]]*//p' "$3/SKILL.md" | head -1 | tr -d ' ')"
  if [ -z "$dep" ]; then return 0; fi
  local deps=() d
  IFS=',' read -r -a deps <<< "$dep"
  for d in ${deps[@]+"${deps[@]}"}; do
    if [ -n "$d" ]; then printf '%s\t%s\n' "$1" "$d" >> "$edges"; fi
  done
}

shopt -s nullglob
for d in "$INHOUSE"/*/; do
  if [ -f "$d/SKILL.md" ]; then add_skill "$(basename "$d")" inhouse "${d%/}"; fi
done
for d in "$VENDOR"/github.com/*/*/*/; do
  if [ -f "$d/SKILL.md" ]; then add_skill "$(basename "$d")" vendor "${d%/}"; fi
done
for d in "$UNKNOWN"/*/; do
  if [ -f "$d/SKILL.md" ]; then add_skill "$(basename "$d")" vendor "${d%/}"; fi
done
shopt -u nullglob

echo '```mermaid'
echo 'flowchart LR'
while IFS=$'\t' read -r n z || [ -n "${n:-}" ]; do
  z="${z:-vendor}"
  if [ "$z" = inhouse ]; then
    printf '  %s["%s"]\n' "$n" "$n"
  fi
done < "$nodes"
declared=" "
while IFS=$'\t' read -r from to || [ -n "${from:-}" ]; do
  from="${from:-}"; to="${to:-}"
  [ -n "$from" ] && [ -n "$to" ] || continue
  tz="$(zone_of "$to")"
  if [ "$tz" = missing ]; then
    printf '  %s["%s ⚠ missing"]:::broken\n' "$to" "$to"
    broken=$((broken + 1))
  fi
  case "$declared" in
    *" $to "*) ;;
    *)
      declared="$declared$to "
      if [ "$tz" = vendor ]; then printf '  %s["%s"]:::vendor\n' "$to" "$to"; fi
      ;;
  esac
  printf '  %s --> %s\n' "$from" "$to"
done < "$edges"
cat <<'EOF'
  classDef broken fill:#fee,stroke:#c00;
  classDef vendor fill:#f4f4f4,stroke:#999,stroke-dasharray:4;
EOF
echo '```'

echo
echo "## Integrity"
total_edges="$(grep -c . "$edges" || true)"
total_nodes="$(grep -c . "$nodes" || true)"
echo "skills: $total_nodes, depends-on edges: $total_edges, broken: $broken"
# deployed-drift: edges whose target is not on node
while IFS=$'\t' read -r from to || [ -n "${from:-}" ]; do
  [ -n "${from:-}" ] || continue
  if [ ! -d "$NODE_SKILLS/$to" ]; then
    echo "UNDEPLOYED: $from -> $to (target missing on node)"
    undeployed=$((undeployed + 1))
  fi
done < "$edges"
if [ "$broken" -eq 0 ] && [ "$undeployed" -eq 0 ]; then
  echo "all dependency edges resolve and are deployed ✓"
fi
exit "$broken"
