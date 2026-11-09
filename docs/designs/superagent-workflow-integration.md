# 设计：feature-dev / bugfix 工作流 × dsh-superagent（Rev.3，agents-only）

| 项 | 值 |
|---|---|
| Owner | agent（本 issue 的 worker） |
| 状态 | Rev.3.1 Approved（2026-11-09；design issue #2；AC-1..8 + 1 票 dry run） |
| 日期 | 2026-11-08 |
| 关联需求 | #1 |
| 关联规范 | P 的 `docs/agents/feature-workflow.md`、`docs/agents/bugfix-workflow.md`、`harness/deepseek-harness/superagent-runbook.md`；V 的 `AGENTS.md`、`docs/agents/feature-workflow.md` |
| 前序设计 | `docs/designs/superagent-egm-closed-loop.md`（Rev.1；Rev.3 取代其 §2/§3 流程段） |
| 评审 | round-1 5 lens（39🔴）；round-2 5 lens（Rev.2 未过）；round-3 consolidated（6🔴：3 修 + 3 条件 AC-1..8） |

> 本文件由设计 issue #2 的 Rev.3.1 导出。批准：飞书 message `fae4a4868e85b24821de688dc3b1ff96`（2026-11-09T00:53:00Z）；AC-1..8 见 §15。

## 0. 两个仓库（P / V）——Rev.2 最大的坑

| 角色 | 仓库 | 用途 | 现状 |
|---|---|---|---|
| **P** | `jerry-jibu/agents`（public） | 流程/设计/runbook/标签/技能；本设计 issue #1/#2 在这里 | 有 `docs/designs/`、`docs/agents/`、`harness/`、`hack/doctor.sh`、已建标签；无 `AGENTS.md`、无 `docs/to-implement/`、无 CI、无 issue 模板 |
| **V** | 一次性私有 sandbox repo（**已确认**；repo 名待定；不用生产产品仓） | 验证 feature 的目标 repo：需求/设计/SPEC/工单/plan/PR 都在这里 | 需创建：简单 CI、`docs/design/`、`docs/to-implement/`、`AGENTS.md`、`docs/agents/`（setup）、本设计新增 labels/templates |

- 本设计的交付 PR **只改 P**（流程文档/runbook/标签脚本/设计文档）。V 的 bootstrap（setup/labels/templates/AGENTS 段）是**验证前置**，在 V 单独做，不属于本设计 PR。
- 本设计 issue #2 的 S2 设计文档落 **P**：`docs/designs/superagent-workflow-integration.md`；验证 feature 的设计文档落 **V**：`docs/design/NN-<slug>-design.md`（跟随 V 的 feature-workflow）。
- Source：验证时 superagent Source 指向 V；用**独立 validation profile**（或切换后回滚）；当前生产 Source 不动。P 的文档 PR 是跨仓 PR，不绑定本 Ticket，以 #2 评论记录链接。

## 1. 主体与术语

| 主体 | 定义 |
|---|---|
| `O` | 操作者侧交互会话（人 + Claude Code/ZCode）；本版需求/设计访谈按 D2 由 W 在 Feishu 承担，O 作为备份 |
| `W` | superagent worker（`worker-<ticketId>`，每票 fresh session） |
| `R` | router/orchestrator，只路由/汇报 |
| `T` | superagent Ticket；实现票与 GitHub 工单 **1:1**；元票（SPEC/拆票）1:SPEC；drift 票 1:drift issue；重试 N:1（同一 T 的补充 input） |

**技能加载**：`egm-*`/`to-spec`/`to-tickets`/`implement` 的 SKILL.md 都是 `disable-model-invocation: true`；W 不依赖 `/name` 注入，派单文本显式给 `~/.agents/skills/<name>/SKILL.md` 绝对路径，W `read` 后按其步骤执行（含各技能的交互门，见 §3）。

## 2. 人在环边界

**3 个阻塞审批门**（人必须裁决）：
1. 需求 review（S1）
2. 设计 review（S2）
3. PR review + merge（S6）

**1 个非阻塞通知**：拆票后的 DAG 通知（S4）——人 24h 内可反对；不反对则继续。

**1 个临时调度动作**：逐票飞书 @（S5）——本版；若 D3 的 Action-bot 派单探针通过，则移除，回到 3 门。

**D4 单账号约束**：所有人工门的记录走**飞书**（人的消息 + 时间）；W 把决定与消息链接回填 issue 评论；**不依赖 GitHub 人评论/签收**（同账号会被 source 判为 agent 自己）。`approved` 标签由 W 按人的飞书指令打，记录以飞书消息为准。

**P0 验证范围**：到 S6 merge + S8 drift report；S8 的 sign-off/归档不在 P0（留后续）。

### 2.1 审计记录（D4 单账号）

- 人的每个阻塞门决定 = 一条飞书消息（人发的）；W 在 issue 上回填：`决定: APPROVED/REJECTED；时间；飞书消息 message_id；摘要`。公开 P 仓库不写飞书链接/聊天 id；私有 ops 日志可存链接。
- `approved` label 由 W 按人的飞书指令打；label 只是索引，审计以飞书消息 + issue 回填为准。
- 禁止把“agent 自己发的 GitHub 评论”当作人的批准。

## 3. 技能 headless 协议（W 在无人环下怎么过技能的门）

| 技能 | 交互门 | W 的处理 |
|---|---|---|
| grill 式访谈 | 多轮开放问题 | 每轮一个 `human_action`，≤100 词；回答记入 issue；W 判断何时收敛 |
| egm-brainstorm / draft | 分节/定向 gate | W 用 `uninterrupted` 跑完，产出全文草案 + 关键分歧清单；只把关键决策问人（1 问） |
| egm-review | `uninterrupted`（5 阶段）vs `feature_spec`（4 阶段，带 checkpoint） | 选 **`uninterrupted`**：5 阶段无 checkpoint，报告写文件；不用 `feature_spec` |
| to-spec | 确认 seams | W 在 SPEC 草案里列 seams，发 issue 评论；人一次确认（飞书） |
| to-tickets | 拆票 quiz | W 在 issue 发拆票方案 + DAG；人通过 24h DAG 通知确认/反对 |
| implement | 无 | W 直接按 ticket + plan 执行 |
| egm-drift-report | 无 | W 只报不修；报告发 SPEC 评论 |

**派单文本必须带**：`TargetFile`（绝对路径）、`Step`（如 `uninterrupted`）、`GoldfishContext`（需求/设计/plan 路径）、`ReportDir`（`docs/design(s)/reviews/<slug>/`）、技能 SKILL.md 路径。

### 3.1 派单模板（W 收到后按路径 read SKILL.md）

```
@deepseek-harness 开始设计 <需求 issue URL>
TargetFile=<设计文档绝对路径> Step=uninterrupted
GoldfishContext=<需求 issue, P 的 docs/agents/feature-workflow.md, V 的 AGENTS.md>
ReportDir=<V 的私有 reviews/ 或未跟踪目录；不提交到 public P>
读 ~/.agents/skills/egm-brainstorm/SKILL.md、egm-draft/SKILL.md、egm-review/SKILL.md

@deepseek-harness to-spec <设计 issue URL；含 design commit SHA>
TargetFile=<设计文档绝对路径>
读 ~/.agents/skills/to-spec/SKILL.md；完成后读 to-tickets/SKILL.md
（to-spec/to-tickets 是独立技能，没有 Step 参数；S3/S4 同一 T 内完成）

@deepseek-harness 实现 <工单 URL>
TargetFile=<工单+plan 路径>
读 ~/.agents/skills/implement/SKILL.md、tdd/SKILL.md、code-review/SKILL.md

@deepseek-harness 对 <SPEC/设计> 做一致性评审
TargetFile=<设计文档 commit>
读 ~/.agents/skills/egm-drift-report/SKILL.md
```

- `Step` 只用于 egm-review（`uninterrupted`）；不要用 `feature_spec`（§3 已排除）、不要发明 `implement/drift` Step。
- 重试：同一 T 的补充/重试 = **同一话题**（N:1）；新工单 = **新话题**（1:1）。失败重试加 `attempt=N`；不要只改 issue 正文。
- `uninterrupted` 是 Rev.1 里的 P3 实验；P0 探针 1 验证。失败回退：egm-review 由操作者侧会话跑，报告回链 issue。

## 4. 阶段表（P 的本设计 / V 的验证 feature 共用；仓库按 §0）

| 阶段 | 主体 | 输入 | 动作 | 输出（落点） | 完成判据 | 门（记录） | 失败路径 |
|---|---|---|---|---|---|---|---|
| S0 需求访谈 | W+人 | 想法 | Feishu 一问一答 | 需求 issue 草案（V；含摘要+飞书链接） | 目标/范围/非目标/验收齐 | 人建 issue（飞书消息） | 无结论→停 |
| S1 需求定型 | W+人 | 草案 | 多轮 review/修订 | 需求 issue（V，`requirements`） | 人无未决 | 人飞书批准（消息链接回填） | 3 轮未收敛→人裁决 |
| S2 设计 | W+人 | 需求 issue | egm 讨论→设计文档 PR/commit→egm-review（uninterrupted，报告入 `reviews/`） | 设计 issue（V，`design`）+ 设计文档（V `docs/design/NN-*.md`，main commit SHA；proposal/ADR/concepts_brief 按 V 的 FW） | 五阶段无 Blocker；Major 有处置；commit SHA 记录在 design issue | 人飞书批准（+`approved` 标签） | 超 2 轮→人裁决 |
| S3 to-spec | W（元票） | 设计文档 commit SHA | 生成 SPEC | SPEC issue（V，`SPEC: `+`ready-for-agent`） | 四段齐+设计链接 | 无独立人门（并入 S4 DAG 通知） | 设计缺口→回 S2 |
| S4 拆票+plan | W（元票） | SPEC | 拆票+DAG+plan | tickets（`Part of #SPEC`）+ `docs/to-implement/NNN-*.md` + README | DAG 无环；plan 与 native deps 一致 | 人 24h DAG 通知（飞书，可反对） | 反对→回 S4 |
| S5 派单 | 人/Action-bot | plan frontier | 新 Feishu 话题 @ 或 Action bot 评论 | 新 T（一票一会话） | T↔工单 1:1；ticket 名固定（分支在 S6 创建） | 派单消息/评论 | 乱序→停，等前置 merge 后重派（不循环） |
| S6 实现 | W（fresh） | 工单+plan+已合并 base | implement+tdd+门禁+PR | 每票 1 PR（`agent/<ticket>`；正文 `Part of #SPEC`、`Fixes #N`、门禁证据、关闭四件套） | 门禁全绿+验收逐条+安全自查 | 人 PR review（飞书反馈，1 轮；需要时第 2 轮）+ merge（squash） | 连续 2 次拒→停 |
| S7 回写 | W（同 PR） | PR | PR 内含 plan 状态 `✅ CLOSED`+README/frontier | plan/README diff | merge 即生效；下票派单前检查 | 人 merge | 漏写→派单器/人拒绝派 |
| S8 drift | W | 全部关闭+设计 | egm-drift-report（只报） | SPEC 评论报告 | 三类归因齐全 | 人裁决（P0 不含归档） | 设计被违反→立票 |

## 5. 分支 / worktree / PR / 认领

- W 用 superagent 原生 worktree + `agent/<ticket>` 分支；**不另建第二 worktree**。V 的 `feat/issue-<N>` 只用于人工分支；V 的 `AGENTS.md` 增 “Executing agent tickets” 例外。
- 认领：W 在工单上 `--add-assignee @me` + 一条 comment（分支名/切片计划）；同账号下这是记录，不用于身份区分。
- PR：title = conventional commit；body 含 `Part of #SPEC`、`Fixes #N`、门禁证据、关闭四件套（commit/证据/遗留/回归）；squash merge；人 merge。
- 一次一票：验证 profile `maxWorkers=1`，或派单器检查 plan/merge 后才派下一票；DAG 的 `blocked_by` 由派单器（人/ Action bot）读取，superagent 本身不读。

## 6. 派单与自动派单（D3）

- 本版默认：**人逐票飞书 @**（新话题），记为需求 #1 的显式偏差（多一个调度动作，不是审批门）。
- D3 探针：V 的 GitHub Action 读 `origin/main` 的 plan/frontier + `blocked_by`，以 `github-actions[bot]` 身份发评论；superagent Source 的 bots 名单 + `observeComments` + accept mode `auto` + rule（`ready-for-agent` + SPEC 范围）+ assignee 幂等 → 自动建 T。**不改 superagent 源码**；Action YAML 在 V。
- 若探针失败：回人工 @，写偏差并由需求方确认；不声称原生 auto 存在（原型无 `blocked_by`/frontier 读取）。

### 6.1 V sandbox bootstrap / Source / Action-bot

1. 创建一次性私有 sandbox（名待定）：`gh repo create <name> --private`；加简单 CI（build/test 一条）。
2. V 初始化：`docs/design/`、`docs/to-implement/`、`AGENTS.md`、`docs/agents/`；若未 setup 则跑 `/setup-matt-pocock-skills`（交互，按 §3 一问一答），再补 labels/templates（§7）。
3. 分支保护：main 要求 PR + CI，`enforce_admins`；不设 required review approvals（D4）。
4. Source：新建 validation profile（或临时切换）指向 V；记录 `repository/prepare/policy` 改动；验证完回滚。当前生产 profile 不动。
5. Action-bot 派单（D3 探针）：V 的 `.github/workflows/dispatch.yml` 读 `origin/main` 的 plan/frontier + `blocked_by`，以 `github-actions[bot]` 发评论；superagent source 的 `bots` 名单含该 bot + `observeComments=true` + accept mode `auto` + rule（`ready-for-agent` + SPEC 范围）+ assignee 幂等。失败回人工 @。

## 7. 交付物 / 标签 / 模板 / setup

| 产物 | 落点 | Owner/阶段 | 验收 |
|---|---|---|---|
| 本设计文档 | P `docs/designs/superagent-workflow-integration.md` | W / 本设计 PR | round-3 通过 + 人批准 |
| runbook 更新 | P `harness/deepseek-harness/superagent-runbook.md` | W / 本设计 PR | 退役旧 §3“四卡点”/§4“五幕”；写新 3 门+S0–S8+切换/回滚 |
| feature-workflow 集成节 | P/V 各自 `docs/agents/feature-workflow.md` | W / P PR；V bootstrap | 两处同步；V 绑定的版本含 superagent 节 |
| label 脚本/表 | P `docs/agents/triage-labels.md`（新增）+ 目标 repo `gh label create` | W / 本设计 PR + V bootstrap | 5 triage + requirements/design/spec/approved/area/*；`gh label list` 断言 |
| issue/PR 模板 | V `.github/ISSUE_TEMPLATE/{requirements,design,ticket}.md` | W / V bootstrap | 三段模板渲染通过 |
| AGENTS 段 | V `AGENTS.md` | W / V bootstrap | “Executing agent tickets”节 |
| plan doc | V `docs/to-implement/NNN-*.md`+README | S4 元票 | 五件套 |
| egm 报告目录 | V 的私有 `reviews/<slug>/`（或未跟踪目录） | W / 各阶段 | **不提交到 public P**（报告含 `/Users/...`、`oc_/ou_`）；P 根已有 8 个 tracked 报告需移除/脱敏 |
| P PR 门 | P | W / 本设计 PR | `hack/doctor.sh` exit 0 + 对应 `NOTES.md` 回写 + 报告目录清理 |

setup：V 先检查 `docs/agents/` 是否已初始化；未初始化则跑 `/setup-matt-pocock-skills`（交互技能，W 按 §3 一问一答；产物 `issue-tracker/domain/triage-labels` + AGENTS 段），再补 labels/templates。

## 8. 安全 / 单账号

- V 必须是一次性私有 sandbox：简单 CI、branch protection（enforce_admins）、无 secret、无真实数据；不使用生产产品仓（其 `make test` 含 real-mount，且 agent 是 admin）。
- D4 单账号：W 可自批/自合；`approved`/merge 的审计以飞书消息为准；branch protection + sandbox 限制影响面，不把“组织边界”当安全边界。
- W 以操作者 OS 用户运行、无审批、`blockedCommands=[]`；guard 仍非目标；V 的一次性/低权限是主要缓解。
- P 是 public：issue/PR 不含 Feishu 私有内容、内网地址、secret；Feishu 链接只记“已记录”或放私有 ops 日志。

### 8.1 Host/secret 基线（R3-02）

- 验证 worker 必须跑在受限环境：独立 OS 用户/容器，只挂 sandbox clone；或至少 `blockedCommands` 配置禁止 `ssh`、`cat ~/.ssh/*`、`cat ~/.lark-cli-dsh-superagent/*`、`cat ~/.dsh/state/superagent/*`、`rm -rf`、`git push origin main`。
- P0 探针加红队项：尝试读 `~/.ssh`、读 `.env`、push main、删 worktree 外文件；必须被拒/失败；否则不开始验证。
- 当前 `blockedCommands=[]`、worker 以操作者 OS 用户运行，是残余风险；不把 prompt 当安全边界。

## 9. 验证计划（P0）

- 目标：V sandbox 的一个 feature，2–3 票（docs-only 或低风险代码，CI 可过）。
- 前置：V setup/labels/templates/AGENTS；branch protection；Source 切到 V（独立 profile 或切换+回滚）；模型路由验证。
- 指标/阈值：人时 ≤45 min/feature（基线：人工/操作者侧同 feature）；elapsed ≤2× 基线；0 重复票；每票 review ≤2 轮；token 预算（记录，超预算停）。
- 通过：S0–S6 走完 + 门禁全绿 + drift 无 Blocker + 人 merge + 人只在 3 个阻塞门（若 D3 通过，则无逐票 @）。
- 中止：同票 2 次 PR 拒；阻塞 >24h；门禁不可过；预算超；任一 → 停、记录、回 Rev.3。
- 失败注入：乱序派单、重复 @、锁文件/窄依赖、只改文档的票、一个跨模块票（看 scope 是否 blocked）。

### 9.1 PR review / merge 策略

- 人 1 轮 PR review；W 按飞书反馈修；需要时第 2 轮；连续 2 次拒 → 停。
- squash merge；PR 标题 = conventional commit；正文含 `Part of #SPEC`、`Fixes #N`、门禁证据、关闭四件套（commit/证据/遗留/回归）。
- plan doc 状态/README 在 PR 内更新，merge 即生效；下票派单前检查 plan/README 指针。

## 10. P0 探针（Rev.3 后、完整验证前）

1. W `read` SKILL.md 并按其步骤走完一轮（含 egm-review `uninterrupted` 5 阶段）。
2. PR 从 `agent/<ticket>` 绑定 T。
3. 新 Feishu 话题→新 T；同话题→补充。
4. 单账号：GitHub 人评论不被 W 收到；飞书回传可用。
5. Action-bot 派单：读 frontier/blocked_by、`github-actions[bot]` 评论、source bots/observe/auto 接受；失败则回人工 @。
6. 人工分钟基线。

## 11. 决策（D1–D6，含 owner/理由/备选）

| # | 决策 | 结论 | 理由/备选 |
|---|---|---|---|
| D1 | P/V/Source | P 文档跨仓 PR；V sandbox；验证用独立 profile 指向 V，回滚 | 生产 Source 不动；备选切 Source |
| D2 | 访谈 | Feishu + headless 协议（§3） | 备选操作者侧（Rev.1） |
| D3 | 派单 | 默认人工 @；Action-bot 探针 | 失败回人工 @，需求方签偏差 |
| D4 | 账号 | 单 GitHub 账号 | 备选独立账号；审计走飞书 |
| D5 | 验证 | **已确认**：一次性私有 sandbox + 2–3 票 + 阈值 | 备选生产仓（需 pre-check/保护/sign-off） |
| D6 | bugfix | P1 | — |

Owner=人；截止=Rev.3 approve 前。D2 是有意的范围反转（Rev.1 §2.1 设计期留操作者侧）；理由：用户要求 Feishu 访谈；补偿：§3 headless 协议 + §10 探针。

## 12. Round-2 响应（keyed）

| Round-2 blocker | Rev.3 处置 |
|---|---|
| R-01 人工门口径/审计 | §2：3 阻塞门 + 1 通知 + 1 临时调度；飞书记录；P0 到 drift |
| R-02 S0–S2 反转/preset | §2/§3：记录 D2；`uninterrupted`；派单带 TargetFile/Step/ReportDir |
| R-03 阶段表错位 | §4：S3 并入 S4 通知；S2 记 commit SHA；S5 DoD 只查 T；S7 输入 PR/门 merge；失败无自环 |
| R-04 FW 追溯 | §4/§5：S4/S6/S7 + proposal/ADR/merge/关闭四件套/frontier |
| R-05 Owner/artifact | §7：owner/阶段/验收 + P PR 门；setup 交互说明 |
| 单账号审计 | §8：飞书记录；sandbox/branch protection 限影响面 |
| 验证目标 | §0/§11：D5 改一次性私有 sandbox（**已确认**） |
| T↔issue 1:1 | §1：实现 1:1；元票 1:SPEC；重试 N:1 |
| egm 报告落点 | §7：reviews/ 目录 + P 根清理 |
| Action-bot 派单 | §6/§10：探针；失败回人工 @ |

## 14. 实施前待办（to-spec/plan 关闭）

- P 根 8 个 egm 报告文件：移入 `docs/designs/reviews/` 或删除；新报告只写 `reviews/`。
- 需求 #1 回写：评论链接 Rev.3；#2 在 review 通过后打 `approved`。
- P 设计文档：`docs/designs/superagent-workflow-integration.md`（本 PR）。
- V sandbox repo 名/创建；validation profile 的 Source/prepare/policy 改动与回滚命令。
- runbook：退役旧 §3“四卡点”/§4“五幕”，写入 S0–S8 + 切换/回滚 + 去重/重试/面板 token。
- P/V 两份 feature-workflow 的同步节（V 绑定的版本含 superagent 节）。

## 13. 风险 / 非目标 / 待定

- 风险：单账号审计弱；W 无 guard；Feishu 访谈轮次多；DAG 乱序；V 构建缺 `dist`（选 sandbox 简单 CI 规避）；双契约漂移（设计文档 commit 为基线）。
- 非目标：superagent 源码改动、工具 guard、bugfix、多 feature 并行、drift 归档自动化、独立 agent 账号。
- 待定：V sandbox 的 repo 名/创建（D5 已确认用 sandbox）；P 设计文档编号；round-3 findings 处置。

## 15. Approve conditions（带 owner/日期；to-spec 前关闭）

| # | 条件 | Owner | 截止 |
|---|---|---|---|
| AC-1 | V bootstrap B0：创建 sandbox、setup、labels（`gh label create` 命令表）、PR/issue 模板、AGENTS “Executing agent tickets” 精确文本、CI job 名、branch protection；验收命令 | W | S0 前 |
| AC-2 | V + validation profile 实例：profile 路径、Source/prepare/policy、drain/游标；双实例同群是否双投的验证 | W | S0 前 |
| AC-3 | 本设计 P 交付 PR 机制：W 克隆 P → 分支 → push → `gh pr create` → `hack/doctor.sh` → 人 merge；PR 链接回填 #2（不绑定 T） | W | 本设计 PR |
| AC-4 | 1 票 dry run（复用 runbook §4 五幕）在完整 2–3 票验证前跑通 | W+人 | 完整验证前 |
| AC-5 | 基线/预算数字：同 feature 人工/操作者侧基线（或固定阈值 45 min/feature、2M tokens/feature）；≤2× 基线 | 人 | 验证前 |
| AC-6 | S8 drift 票的 GitHub issue 落点（drift issue 或 SPEC 评论）与 T↔issue 映射 | W | S8 前 |
| AC-7 | headless 4 洞：brainstorm/draft 分节、seam 决策记录、S0 最多 3 轮、失败/升级 24h 模板 | W | S0 前 |
| AC-8 | labels/PR 模板/CI job/plan-claim 检查命令；§12 编号化 | W | S0 前 |
| AC-9 | PR/issue 自动通知：validation profile 的 Source=sandbox + `observePulls/Issues/Comments`；PR/issue thread 订阅；merge/close/comment 时 worker 发飞书；单账号下人的事件可能被 source 当 agent 自身丢弃 → 飞书轮询/第二身份兜底；sandbox 跨仓用 poller | W | validation 前 |
