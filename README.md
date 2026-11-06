# agents

Centralized AI Agent Skills repository (`skills/`), shared across Claude Code (`~/.claude/skills`) and Gemini Antigravity (`~/.gemini/config/skills`).

## Directory Structure

- `skills/` — All agent skills (`SKILL.md`, `references/`, `assets/`, `scripts/`), including:
  - **`code-walk`**: 4-Tier Deep Dive Code Walk & Modifiability Engine (with Dual-Axis Adversarial Audit, Blast Radius Matrix, and interactive Document/Slideshow HTML templates).
  - **`archify`** / **`diagram-design`**: Validated architecture, topology, sequence, and state diagrams.
  - **`grill-me`** / **`grilling`**: Design tree interview & stress-testing.
  - **`teach`** / **`retro`** / **`skill-creator`**: Interactive teaching, session retrospectives, and skill authoring.
  - **`code-review`** / **`refactor`** / **`tdd`**: Multi-axis code review, refactoring, and test-driven development.
  - **`egm-*`**: Elephant-Goldfish Model suite (brainstorm → draft → review → review-loop → resolve, plus bootstrap & drift-report), installed from [google/elephant-goldfish-model](https://github.com/google/elephant-goldfish-model). Each skill carries its own copies of the repo's shared `agents/`, `resources/`, `docs/` trees (SKILL.md paths resolve against the plugin root).
- `.skill-lock.json` — Installed skill lock metadata.
- `agents/` — Canonical subagent definitions (markdown: `name`/`description`/`tools` frontmatter + system-prompt body), deployed to every agent harness on this node. Includes the **`egm-*`** Goldfish reviewer personas (design, structural, style, comprehension, codebase-details, implementation-readiness, inventive-catalyst, zoom-out) plus orchestrators (synthesizer, bootstrap-orchestrator).
- `hack/` — Node skill/agent sync tooling:
  - **`sync-skills.sh`**: `pull` (install/refresh skills from remote sources onto this node + mirror into this repo), `backup` (node → repo, additive), `snapshot` (backup + git commit), `restore [skill...]` (repo → node), `agents` (regenerate subagent defs from skills, collect + deploy), `list`.
  - **`sync-agents.sh`**: `collect` (node `~/.zcode/agents` → repo store), `deploy [zcode|claude|antigravity|deepseek]` (repo store → harness agents dirs, converting `tools` frontmatter: array for zcode/antigravity, comma-list for claude/deepseek), `list` (per-harness deployment status).
  - **`sources.conf`**: remote skill sources, one per line as `url|skills_subdir|shared_dirs`. Add a line to track another repo.

## Node layout

Real skill dirs live in `~/.agents/skills/` (shared across tools); tool-specific
skill dirs are symlinks, e.g. `~/.zcode/skills/<name> -> ../../.agents/skills/<name>`.
Agent definitions deploy to `~/.zcode/agents/`, `~/.claude/agents/`,
`~/.gemini/config/agents/`, `~/.deepseek/agents/` (paths overridable via env
`ZCODE_AGENTS_DIR`, `CLAUDE_AGENTS_DIR`, `ANTIGRAVITY_AGENTS_DIR`, `DEEPSEEK_AGENTS_DIR`).

```sh
# refresh skills + agents on this node from all remote sources, then snapshot:
hack/sync-skills.sh pull && hack/sync-skills.sh snapshot

# add a powerful agent by hand: write agents/<name>.md, then
hack/sync-agents.sh deploy
```
