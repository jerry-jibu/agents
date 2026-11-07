# agents

Personal agent-environment repository: skills, subagent personas, MCP configs,
and delivery workflows — governed as a git-first backup & deployment unit for
four harnesses: **ZCode**, **Claude Code**, **Antigravity**, **deepseek-harness**.

> Governance design: [docs/designs/multi-harness-agent-repo-governance.md](docs/designs/multi-harness-agent-repo-governance.md)
> (Rev.4 Approved — dual-zone layout, git as single source of truth, delta-guarded
> materialization, expectation-based doctor).

## Data-flow law

**The git repo is the single source of truth; node (`~/.agents/skills`) is a pure
deployment target.** Edits happen in the repo; nodes sync via git
commit/push/pull; `pull` runs on ONE authoritative node only.

```text
upstream ──pull──▶ vendor/github.com/<owner>/<repo>/<skill>/   (pull-only mirror)
in-house/skills/  ──(edit in repo, git commit)──▶ [git repo = authority]
[git repo] ──restore (delta-guarded)──▶ node ~/.agents/skills/ (flat, shared root)
node drift ──adopt (diff + confirm)──▶ repo (harvest / promote / fork)
```

## Directory structure

- `vendor/github.com/<owner>/<repo>/<skill>/` — upstream mirrors, pull-only
  (mattpocock/skills, addyosmani/agent-skills, google/elephant-goldfish-model,
  tt-a1i/archify, modem-dev/sideshow, cathrynlavery/diagram-design + frozen
  leftovers of vercel-labs/*, anthropics/skills, GoogleChrome/modern-web-guidance,
  yizhiyanhua-ai/fireworks-tech-graph). Per-skill granularity: skills an upstream
  deletes survive here.
- `vendor/unknown/` — 16 frozen, unattributed skills (`FROZEN.md` manifest;
  pull never touches; promote via `adopt` or retire).
- `in-house/skills/` — self-authored skills (code-walk, code-to-spec,
  architecture-diagram, insight-diagram). Git is the version record — not in the
  lock. `depends-on:` frontmatter declares skill dependencies.
- `agents/` — canonical subagent personas (10 egm-*.md), deployed to
  zcode/claude/antigravity (deepseek runtime-delegates — no personal dir).
- `mcps/` — MCP service definitions. Currently **sideshow** (web server on
  `localhost:8228`, HTTP MCP for zcode, stdio for the rest).
- `harness/<name>/` — per-harness governance: `NOTES.md` (verified mechanism
  notes + dates), `config/` (credential-scanned backups), `expected.json`
  (Stage 2: machine-readable expectation state, doctor `--live` SSOT).
- `docs/agents/` — generalized feature/bugfix delivery workflow templates.
- `docs/designs/` — governance design documents.
- `.skill-lock.json` — v4: sources registry (live + `frozen: true`), per-skill
  commit anchors (`commit`/`pulledAt`), deployedHash baselines for the delta
  guard (`skills` + `inHouse` sections).
- `hack/` — tooling:
  - **`sync-skills.sh`**: `pull [source-id]` (upstream → vendor + lock anchors +
    auto-restore; worktree-clean guard; per-skill mirror; collision hard-fail),
    `restore [--force] [name...]` (repo → node, delta-guarded by deployedHash
    baselines; in-house wins name collisions; frozen zones never written to
    lock), `adopt <name>` (node drift → git: harvest/promote/fork with
    `forked-from` marker), `collect` (harness config backups, credential-
    scanned), `agents` (regenerate `~/.zcode/agents` personas), `list`.
  - **`doctor.sh`**: expectation-vs-reality checks — v0 static: C1 frontmatter
    (in-house=error / mirror=warn), C2 depends-on resolution, C3 zcode skills
    dedup, C4 repo↔node parity + content drift, C6 strays; `--fix` whitelist;
    Stage 2 adds C5 lock consistency + C7 `--live` MCP handshake.
  - **`lib-hash.sh`**: shared deployedHash algorithm (sync + doctor).
  - **`sync-agents.sh`**: `collect` / `deploy [zcode|claude|antigravity]` / `list`.
  - **`sync-mcps.sh`**: MCP service lifecycle + per-harness config writing.
  - **`sources.conf`**: `url|skills_subdir|shared_dirs` per line
    (egm, mattpocock, archify, sideshow; addyosmani + diagram-design join in Stage 2).

## Node layout

`~/.agents/skills/` is the single user-scope skills root — ZCode and
deepseek-harness read it natively (zero extra deployment); `~/.zcode/skills/`
must stay EMPTY (dual-root scanning would duplicate every skill; doctor C3
enforces). Agent dirs: `~/.zcode/agents/`, `~/.claude/agents/`,
`~/.gemini/config/agents/` (env-overridable `*_AGENTS_DIR`). MCP configs:
`~/.zcode/cli/config.json` (`mcp.servers`), `~/.claude.json`,
`~/.gemini/config/mcp.json`, deepseek path pending verification — see
`harness/<name>/NOTES.md` for verified mechanics and dates.

```sh
# daily driver (authoritative node):
hack/sync-skills.sh pull          # upstream -> vendor -> this node (guarded)
git add -A && git commit          # publish; other nodes: git pull + restore

# health:
hack/doctor.sh                    # static; exit code = error count

# node-side drift (hand-edited a skill on node?):
hack/sync-skills.sh adopt <name>  # diff + confirm -> into git (or restore --force to discard)

# agents + MCP:
hack/sync-agents.sh collect && hack/sync-agents.sh deploy
hack/sync-mcps.sh status          # ... start / stop / configure
```

## New machine bootstrap

```sh
git clone git@github.com:jerry-jibu/agents.git && cd agents
hack/sync-skills.sh restore       # materialize 104 skills (delta guard is a
                                  # no-op on an empty node)
hack/sync-agents.sh deploy && hack/sync-mcps.sh configure
hack/doctor.sh                    # must exit 0
```

(Stage 2 replaces the manual sequence with `hack/setup.sh --level 3`.)
