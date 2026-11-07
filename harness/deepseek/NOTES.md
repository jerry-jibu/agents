# deepseek-harness (dsh) — 机制说明（NOTES）

* **验证日期**: 2026-11-07（skills 发现机制已验证；mcp 配置路径待会话验证）
* **状态**: skills 零部署为期望态；agents 不适用；mcp 路径待定

## Skills（已验证，源码级）

dsh 原生读取 `~/.agents/skills`——`skill-filesystem` 发现序（packages/skill/
skill-filesystem/src/index.ts + docs/config-catalog.md 实测）：

| rank | source | path |
|---|---|---|
| 200 | project-agents | `<projectRoot>/.agents/skills`（最高） |
| 400 | user-dsh | `<dshHome>/skills`（`$DSH_HOME` 或 `~/.dsh`） |
| 500 | user-agents | `<agentsHome>/skills`（`$DSH_AGENTS_HOME` 或 `~/.agents`） |

即本 repo 的共享根对 dsh **零部署即达**（期望态：skillsExtra 为空）。
Future Improvements 的项目级 skill 子集部署正是利用 rank 200。

## Agents（不适用）

dsh 的 subagent 是运行时委托（in-process / ACP / Claude-Code / Codex adapter，
packages/subagent），**无个人 named-subagent 目录**。`~/.deepseek/agents/` 是
错误猜测（Stage 0 已删除死配置）；`sync-agents.sh` 的 deepseek 目标已移除。

## MCP（待会话验证）

dsh 配置根在 `~/.dsh/`（`$DSH_HOME`）；当前 `~/.deepseek/mcp.json` 属路径猜测
（Stage 0 保留观察）。**验证方法**：开一个 dsh 会话，确认其 MCP 配置真实读取
路径（`~/.dsh/` 下何处、格式），结论回填本文件与 expected.json；届时
`sync-mcps.sh` 的 deepseek 写入路径按结论修正。
