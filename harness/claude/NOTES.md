# Claude Code — 机制说明（NOTES）

* **验证日期**: 2026-11-07（agents 面已验证；skills/mcp 面为待验证记录）
* **状态**: agents 已验证 live；skills 读取路径与 mcp 配置为 experimental 待验证

## Agents（已验证）

`~/.claude/agents/` — 10 个 persona 由 `sync-agents.sh deploy` 写入（comma 格式
tools frontmatter）。2026-11-07 实测部署后文件在位。

## Skills（experimental，待一次会话验证）

预期 `~/.claude/skills/`（惯例路径），当前为空目录。验证方法：新开 Claude Code
会话，确认 skill 列表来自 `~/.agents/skills` 还是 `~/.claude/skills`，或两者
双读（若是双读，期望态为 symlink 单发现版或清空其一——参照 zcode Q1 教训）。
结论回填本文件并更新 `expected.json` 的 `unverified`。

## MCP（路径按惯例，未会话验证）

`~/.claude.json` → `mcpServers`（stdio entry：`npm run mcp`，代理到 sideshow
:8228 服务）。`~/.claude.json` 同时承载会话历史等大状态，**collect 有意不备份
该文件**（凭据扫描外的大状态文件，脱敏成本高）——仅备份经过裁剪的 MCP 片段，
待验证后确定裁剪方案。

## 前次部署状态（迁移前遗留，待验证清点）

迁移前 `sync-agents.sh` 曾向本 harness 部署（handoff 记录"files written, not
verified in harness"）。
