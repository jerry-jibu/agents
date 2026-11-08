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

## CLI 形态与 superagent 部署（2026-11-08，已验证）

* **dsh CLI**：npm 全局 `@deepseek-ai/dsh@0.2.2-rc.1`（bin 落 `~/.npm-global/bin/dsh`，
  `~/.npmrc` prefix 继续生效）。**node 必须 ≥24.9**（npm 包 engines）——经
  `brew install node@24` + `~/.zshrc` 前置 `/opt/homebrew/opt/node@24/bin` 解决；
  nvm 因与该 prefix 不兼容弃用。当前共 3 个 node 来源：`/usr/local/bin`（22.18，系统 pkg）、
  `~/.hermes/node/bin`、`/opt/homebrew/opt/node@24`（dsh 用）。
* **superagent profile**（`dsh-superagent-prototype` bundle 常驻服务）：
  - profile：`~/.dsh/profiles/superagent`（web 模板 + `dsh plugin add link:<checkout>`），
    bundles = dsh-base + dsh-web-app + dsh-superagent；机器配置在 profile 的
    `cordis.patch.yml`（stateDir=`~/.dsh/state/superagent`、端口 3082、feishu 插件行）
  - 服务管理：checkout 内 `scripts/dsh-superagent start|stop|restart|status`（tmux 会话
    `dsh-superagent`；status 退出码 0/1/2/3 = 正常/不运行/部件错/等 setup）
  - 管理面：`http://127.0.0.1:3082/orchestrator/api/` + 头 `x-orchestrator-request: 1`
    （settings/prompts/state 路由，docs/006-deployment.md）
  - worker 隔离两层：环境层（`stateDir/worker-bin` shims 置 PATH 首、
    `worker-gitconfig` 替换 git 配置并把 github.com credential helper 指向 agent CLI、
    SSH→HTTPS 重写、剥 GH_TOKEN）+ 工具白名单（worker 预设）；**无工具调用层 guard**
    （`tools/pre-execute` 未挂监听）——闭环设计文档
    [docs/designs/superagent-egm-closed-loop.md](../docs/designs/superagent-egm-closed-loop.md) §4 有方案
* **skills 结论复核（CLI 形态同样成立）**：superagent 的 router/worker agent 预设均含
  `skill-filesystem` + `tool-skill`，rank 500 读 `~/.agents/skills`——本 repo 169 个技能
  对 worker 会话零部署可见；项目级走 rank 200 `<projectRoot>/.agents/skills`。
  团队技能另有独立通道（prompts API，命名 `dsh-superagent-<name>`，保留名 feishu/github），
  与共享根互不影响。
* **桌面版与 CLI 共存**：共用 `~/.dsh`（不同 profile 互不干扰）；模型凭据在 DSH_HOME 级共享
  （CLI 的 superagent profile 未单独配模型即 ready）。
* **headless profile 凭据策略（2026-11-08 实证）**：出厂 `disabled: true` 禁用 credentials
  行，`--patch` 启用后仍缺 key——`~/.dsh/.credentials.yaml` 存的是**平台账号 token**
  （`deepseek-account-platform/default`，issuer `https://platform.deepseek.com`，桌面版登录
  写入），而 headless 的 `agent-default-model` 指向 API-key route `deepseek-official`；改
  patch 到 `deepseek-account` route 后仍报 `ACCOUNT_SIGN_IN_REQUIRED`（destination 校验不
  放行，`$DEEPSEEK_BASE_URL` 指向平台亦无效）。**结论：headless/CI 场景需要真正的
  `DEEPSEEK_API_KEY`（环境变量 → `<cwd>/.env` → `$DSH_HOME/.env`），账号 token 只服务
  web/desktop 系 profile 的模型路由。**
* **飞书 bot 专属 CLI（2026-11-08，已验证）**：`~/.lark-cli-dsh-superagent/`（独立配置目录，
  与个人 lark-cli 共享 keychain 的 app secret 条目——只删目录，勿跑 `config remove`）；
  `config strict-mode bot --global` 后 `users: (no logged-in users)`。wrapper
  `~/.local/bin/lark-bot` 注入该 env。**本机 lark-cli 1.0.56（文档测试 1.0.90）**：bot
  能力未开通时 `/open-apis/bot/v3/info` 返回 `11205 app do not have bot`（排查信号：
  开发者后台加"机器人"能力 + 发版后即消）；开通后 v3/info 返回 `ok:true` 但 `data` 为空
  （open_id 不在此接口）。super-agent setup 另读 app id / brand / bot open_id——保存
  feishu source 时由其自行校验。
