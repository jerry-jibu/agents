# dsh-superagent 部署与流程验证 Runbook

> 2026-11-08 首次部署实录 + 使用方式 + P0 流程验证剧本。
> 机器/机制事实的权威归宿是 [NOTES.md](NOTES.md)（本文引用不重述）；闭环工作流设计是
> [docs/designs/superagent-egm-closed-loop.md](../../docs/designs/superagent-egm-closed-loop.md)。
> **安全**：飞书 App Secret、面板 token 只存在于本地配置（`~/.lark-cli-dsh-superagent/`、
> `.artifacts/` 日志），不入任何仓库与 issue。App ID 在本文以 `cli_aa7a…` 脱敏。

## 1. 部署过程（含全部踩坑）

### 1.1 环境修复

| 项 | 结果 |
|---|---|
| node | `brew install node@24`（v24.22.2，≥24.9 满足 dsh npm 包 engines）+ `~/.zshrc` 前置 `/opt/homebrew/opt/node@24/bin`。**nvm 因 `~/.npmrc` 的 `prefix=~/.npm-global` 不兼容而弃用** |
| tmux | `brew install tmux`（3.8，服务脚本必需） |
| dsh CLI | `npm i -g @deepseek-ai/dsh@0.2.2-rc.1`（bin 落 `~/.npm-global/bin/`）；原生模块 install 脚本被 npm 新机制拦截，须 `--allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs` 重装 |

### 1.2 profile 与服务

```sh
dsh superagent --from-default-profile web --dump-config > /dev/null   # 建档（仅首次）
dsh plugin --profile superagent add "link:<prototype-checkout>"       # 挂 bundle
# ~/.dsh/profiles/superagent/cordis.patch.yml 见 NOTES.md（stateDir/端口/feishu 行/模型路由）
scripts/dsh-superagent start|stop|restart|status                      # tmux 常驻
```

**模型路由（关键坑）**：web 模板默认 `deepseek-official`（API-key 路由），而本机凭据是
桌面版的平台账号 token。修法三层，缺一不可：

1. profile patch：`agent-default-model → provider: deepseek-account, model: deepseek-flash, reasoningEffort: high`（与桌面 profile 一致）
2. settings 钉角色模型：`eval.model` 与 `executor.model` 经管理 API 置同路由
3. **改默认路由后必须重建既有会话**：`model/selection` 在会话创建时持久化，
   `initializeRoleModel` 只播种新会话。master 会话隔离法：
   `stop → mv ~/.dsh/sessions/<cwd-slug>/orchestrator-*  ~/.dsh/quarantine/ → start`
   （会话 id 是确定性 hash，重建自愈）

### 1.3 渠道配置（Management API，头 `x-orchestrator-request: 1`）

| 步骤 | 操作 |
|---|---|
| GitHub source | `PUT settings/source:github`：repo + cli=`/usr/local/bin/gh`（主账号跑通期） |
| policy | github.allowed=[jerry-jibu]；feishu.syncChat=群 id（成员经同步进入 allowed） |
| executor | directory=stateDir/work + prepare（fetch+worktree，模板见 docs/006） |
| prompts | Rev.1 去 auto-merge 段；Rev.2 加 PR 安全自查门槛；Rev.3 加 identities 技能（skills 格式 `{name: body}`，注册自动加前缀 `dsh-superagent-`） |
| 飞书 source | `PUT settings/source:feishu`：cli=wrapper、群 mentions 模式、私聊开 |

**飞书 bot 专属 CLI**：配置目录 `~/.lark-cli-dsh-superagent/`（bot-only strict mode），
wrapper `~/.local/bin/lark-bot`——**exec 路径写死绝对路径**
（`/Users/gyj/.npm-global/bin/lark-cli`）——dsh subprocess 服务的 PATH 解析不可靠，
`which` 解析正确不等于服务里解析正确（本轮实测：重启后仍报旧版错误，钉死才稳）。

**lark-cli 版本坑**：1.0.56 缺 `im +chat-members-list`（policy 同步成员用）→ 升级
`npm i -g @larksuite/cli@latest`（1.0.99）。开发者后台 bot 能力未开通时
`/open-apis/bot/v3/info` 返回 `11205 app do not have bot`。

### 1.4 行为须知（设计使然，勿当 bug）

- **Trigger 幂等去重**：完全相同内容的消息第二次发会被 duplicate 丢弃——重试要换内容
- **面板 token 随重启轮换**：最新地址在最新 `.artifacts/dsh-superagent-superagent-*.log`
- `observe` 模式只约束规则型主动工作；**@ 提及的 explicit 请求任何模式都建单**
- 编辑 issue 正文补 @ 收不到，要发新评论

## 2. 使用方式

| 渠道 | 派单 | 追问 | 叫停 |
|---|---|---|---|
| 飞书群 | `@deepseek-harness <需求>`（DEEPSEEK-superagent 群） | 同话题直接说 | 同话题明说 |
| GitHub | issue 评论 `@jerry-jibu <需求>` | 同 issue 评论 | 同 issue 明说 |

观察面（浏览器）：面板 `http://127.0.0.1:3082`（token 见最新日志）——Superagent 入口
（Overview/Trigger/Eval/Execution/Settings）+ 侧边栏会话列表（orchestrator 主会话与
worker-<ticketId> 全程直播）。桌面 App 绑定 desktop profile，看不到本服务。
运维：`scripts/dsh-superagent status|stop|restart`；底层日志 `tmux attach -t dsh-superagent`。

## 3. 工作流（闭环摘要）

人在环四卡点：**设计 Approve（egm-review checkpoint）→ 扫工单 DAG（约 30 秒）→
PR 验收 merge → 漂移归因裁决**；其余全自动：

```
grill → egm-brainstorm → egm-draft → egm-review(Approved)   [操作者侧]
  → @agent 元票：建 SPEC + 工单 DAG（native dependencies）    [worker]
  → frontier 逐票 @agent → implement（TDD 纪律）→ PR          [worker]
  → @agent 漂移票：egm-drift-report 只报不修 → 报告 PR         [worker，fresh 会话=金鱼性质]
  → 归因三类（实现更优/无伤大雅/设计被违反）→ 归档             [操作者侧]
```

技能分流原则与三根绑定杆（派单评论 / 仓库 AGENTS.md / 团队节）见设计文档 §2.1。
**super-agent 不读 GitHub 依赖**——feature 内串行靠派单纪律（人或 P2 frontier 派单器）。

## 4. P0 五幕验证剧本（本 runbook 的验收目标）

**前置**：feishu/github 双 ready（`status` exit 0）+ 模型路由验证过（见 §1.2 三层）。

| 幕 | 执行者 | 动作 | 观察点 |
|---|---|---|---|
| 0 通路 | 人 | 群里 `@deepseek-harness ping <变化后缀>` | Trigger 页到达；Eval 结论 ignore/ack；**不建票** |
| 1 设计落库 | 操作者侧 | 小 feature 极简设计文档（2 票规模，含 Detailed Implementation Plan）按仓库惯例放 `docs/design/`，commit+push main | 设计是授权母体 |
| 2 元票 | 人 | 群里 `@deepseek-harness 按 docs/design/NN-<slug>.md 创建 SPEC 和工单票（tracer-bullet 纵切、native dependencies）` | 票出现 → worker 建 SPEC+DAG → 群里一句话+链接 |
| 3 扫 DAG+逐票 | 人 | GitHub 扫 DAG → 逐票 `@deepseek-harness 实现 #N（TDD，验证计划见设计文档）`（按 DAG 序，**一次一票**） | 每票 worker 会话、PR、安全自查；人 merge |
| 4 漂移票 | 人 | `@deepseek-harness 对 docs/design/NN 与已合并实现做漂移评审（只报不修），报告提交 PR` | fresh worker 报告 PR → 人归因三类 → merge/立票 |
| 5 复盘 | 操作者侧 | 金鱼纯度（worker 子代理是否收到 persona 外指令）；worker 实际加载的技能；飞书消息噪音（每票几条） | 回写本 runbook 与设计文档 |

## 5. Retro 发现（2026-11-08）

1. **上游 issue 候选**（dsh-superagent-prototype）：setup 增 modelProblem（默认路由启动时廉价解析）；SETUP.md probe 加 `lark-cli --version` 对 engines 检查
2. 机器级事实（node PATH/npm prefix/quarantine 惯例）应建 `harness/machine/NOTES.md`，与各 harness 平级
3. 开场双 Explore agent 扇出（~4.5M 子代理 token）对"理解两个仓库"是正确形态；headless 调试的时间盒（3 次尝试即止损）是应保持的实践
