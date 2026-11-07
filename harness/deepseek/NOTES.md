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

## 运行时故障排查记录（2026-11-07，已修复）

**现象**：桌面版 0.2.2-rc.1（11-04 更新）每次会话报
`workspace create failed: ... active Service "workspaceController" is unavailable`
与 `sessionController` unavailable。

**根因（前台复跑 host 抓获）**：`~/.dsh/sessions/*/` 下 2 个
`*.archived-20261024` 归档会话目录的**身份头未随归档重写**（header 仍指向归档前
路径）——`dsh-workspace` 插件启动时 `assertStoredIdentity` 校验失败 →
`workspaceRegistry` 缺席 → session/workspace-controller pending → gateway 报
unavailable。10-24 当天的归档过程本身有 bug（当天 profile node_modules 也有
变更活动）。

**修复**：2 个损坏归档目录全部隔离到 `~/.dsh/quarantine/`（未删除，可恢复）；
host 重跑验证 corrupt 清零、核心服务全激活。

**遗留（上游 bug，无害）**：`desktop-product-telemetry` 因 app 组合层漏传
`serviceVersion` 而 ValidationError → `product-analytics` 连带 pending。
patch 层无法修（`config:` 是整体替换不是合并，补 serviceVersion 会顶掉
serviceName）——需上游修组合层。上游可报 bug：归档身份头 + 组合层两处。

**调试方法（复用价值）**：fatal 诊断不落盘，前台复跑 host 抓输出——
`ELECTRON_RUN_AS_NODE=1 "/Applications/DeepSeek Harness.app/Contents/MacOS/
DeepSeek Harness" --expose-internals <dsh-desktop-host/lib/index.js> <app.asar/dsh>
<profile> <primary-runtime> <pnpm.mjs> <runtime/bin>`（cwd = profile 目录）。
