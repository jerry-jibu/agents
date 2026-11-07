# Claude Code — 机制说明（NOTES）

* **验证日期**: 2026-11-07（skills 面已验证并落地；模型/端点侧用户自管，见下）
* **状态**: skills = 自有路径 + symlink 农场（restore 自动维护）；agents 已验证；mcp 路径按惯例未会话复验

## Skills（已验证，2026-11-07）

**Claude Code 2.1.312 只读自有路径 `~/.claude/skills/`，不读共享根 `~/.agents/skills`**
（与 dsh/zcode 不同）。验证依据：`~/.claude/skills/` 自 2026-10-05 起存在一条
symlink 农场（→ `../../.agents/skills/<name>`）——历史上正是为了解决"skills 不可见"
而建；本次会话验证确认其必要性。

**处置（restore 自动维护）**：`sync-skills.sh restore` 末尾按
`expected.json`（`skillsExtra` + `skillsExtraMode: symlink-farm`）重建农场——
当前 104 条 symlink 全量对齐共享根，陈旧/断链自动清理。农场是"单发现版"：
claude 只扫这一个目录，无 zcode 式双根重复问题。

## Agents（已验证）

`~/.claude/agents/` — 10 个 persona 由 `sync-agents.sh deploy` 写入（comma 格式
tools frontmatter）。2026-11-07 实测在位。

## 模型/端点（用户自管，非本 repo 治理面）

`~/.claude/settings.json` 将 claude CLI 指向 deepseek 的 Anthropic 兼容端点
（自定义 `ANTHROPIC_BASE_URL` + `ANTHROPIC_MODEL`）。端点 2026-11-07 无鉴权探测
存活（HTTP 401）。**该文件含明文 API token——collect 有意永不备份它**（凭据
排除策略的实际案例）；建议轮换已暴露于会话记录的 token。
若会话级 skills 仍不可见而农场已对齐：排查方向为 CLI 版本的 skills 加载行为
（`claude --debug`）与端点侧模型能力，与本 repo 无关。

## MCP（路径按惯例，未会话复验）

`~/.claude.json` → `mcpServers`（stdio entry：`npm run mcp`，代理到 sideshow
:8228）。`~/.claude.json` 同时承载会话历史等大状态，**collect 不备份**——
仅必要时人工裁剪 MCP 片段。
