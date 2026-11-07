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

## MCP（源码级闭合，2026-11-07）

**dsh 无文件级 MCP 配置**——Web/Desktop profile 挂载 `ctx.mcpManager`，服务器
通过 **App 的 Settings UI** 配置（deepseek-harness 源码
`docs/subsystems/mcp.md`："It runs servers configured through Settings"；
ACP 模式下则由连接方在会话内声明，`packages/acp/acp/src/mcp.ts` 的
`mountAcpMcpServers`，且 stdio `command` 必须绝对路径）。
`~/.deepseek/mcp.json` 属无效猜测——已删除；`sync-mcps.sh` 的 deepseek 写入
目标已移除。要在 dsh 里用 sideshow：在 App Settings → MCP 里手动添加
（stdio：`<绝对路径>/node_modules/.bin/npm run mcp`，sideshow repo 为 cwd；
或 HTTP：`http://localhost:8228/mcp`）。

## 已知运行时问题（2026-11-07，与 skills repo 无关）

DeepSeek Harness 桌面版 0.2.2-rc.1（11-04 更新）报
`workspaceController`/`sessionController` unavailable——gateway 活着但核心服务
未注册；嫌疑为 app 升级后 profile 第三方插件（10-24 安装，0.2.1 时代 API）在
cordis fail-fast 下中断启动链。fatal 诊断只发往 App 诊断面板不落盘
（`apps/desktop-host/src/index.ts` 的 process.send fatal）。
