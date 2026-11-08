# super-agent × egm 自动化交付闭环设计

> Rev.1 Draft — 2026-11-08
> 状态：草案（待 egm-review）
> 关联部署：dsh CLI 0.2.2-rc.1 + `dsh-superagent` profile 常驻服务（GitHub/飞书 → Ticket → worker → PR），面板 `127.0.0.1:3082`
> 关联资产：[feature-workflow.md](../agents/feature-workflow.md)（人在环交付流）、`~/.agents/skills/egm-*`（7 技能 + 10 persona）、super-board（操作者侧看板）

## 1. 动机与缺口

super-agent 把"接单 → 实现 → PR"交给常驻 agent 后，对照现有 feature-workflow 出现三个缺口：

| 缺口 | 现状 | 后果 |
|---|---|---|
| **设计环节缺位** | super-collect / grill-me 只做"发现问题 + 拷问"，无方案设计与对抗评审 | 工单无设计授权依据，worker 自行做架构决策 |
| **实现-设计一致性无人检查** | worker 只对 issue 负责，PR 合并后无人对照设计文档核查 | 文档-代码漂移（EGM 要解决的核心问题） |
| **worker 无工具调用层护栏** | 环境层隔离已有（worker-bin shim / worker-gitconfig / blockedCommands），但工具调用层为空 | worker 可读敏感文件、删工单目录外内容、push 主干 |

## 2. 角色分工（核心决策）

**egm 的 Elephant 需要人在环的交互门（checkpoint、裁决、turn-taking），设计授权是"谁可以派活"的上游** —— 因此：

- **设计期 egm（brainstorm → draft → review）留在操作者侧**（Claude Code / ZCode 会话）。checkpoint 就是审批门本身，不可代跑；Approved 设计 = 授权母体。
- **Approved 之后全自动**：to-spec / to-tickets 以一条元请求派给 super-agent——worker 按方法论建 SPEC issue + 工单 DAG（native dependencies，gh 经 worker shim 可用），人只扫一眼 DAG（约 30 秒，唯一人工卡点）。票是已批准设计的分解，不是新授权。
- **实现按票调度，feature 内默认串行**：票是 Mandate/resume/面板/PR 的单元（`worker-<ticketId>` 一票一会话）；同一 feature 的票用 DAG `blocked_by` 串成"同时一个 worker"，并行只给独立切片——"一个 feature 一个 worker"是 DAG 的涌现结果，不是配置。上下文交接靠已合并 base + 设计文档，不靠 worker 记忆。
- **漂移评审 = 独立的一张票**：fresh worker 天然保留金鱼性质（无实现会话记忆），加载 `egm-drift-report` 技能（只报不修），报告经 PR/评论回到 SPEC；**归因裁决（实现更优/无伤大雅/设计被违反）留给人**。"worker 自审无对抗性"的顾虑只适用于实现者自审——独立漂移票是另一个运动员。

```text
[操作者侧：人在环（不可代跑）]
  super-collect          发现问题 → findings 文档
  grill-with-docs        拷问成 concept
  egm-brainstorm         多透镜攻击 → concepts_brief.md
  egm-draft              设计起草 → docs/design/NN-<slug>-design.md
  egm-review             五阶段评审 → Approved   ← checkpoint 即审批门，授权母体在此产生
        │
        │  一条元请求派单：@jerry-jibu "create SPEC + tickets from design NN"
        ▼
[super-agent：全自动段]
  票1  to-spec/to-tickets  worker 按方法论建 SPEC issue + 工单 DAG（native dependencies）
        │
        │  人扫一眼 DAG（约 30 秒，唯一人工卡点）
        │  frontier 派单器（可选 cron）：新 frontier 票自动 @jerry-jibu
        ▼
  票2..N  implement        worker 按票实现（TDD 纪律 + 验证计划）→ 安全自查 → PR
        │                 feature 内 DAG 串行（同时一个 worker）；独立切片才并行
        │  人验收 PR → merge（每票一个 PR = 一个 review 单元）
        ▼
  票N+1  drift review      fresh worker（金鱼性质：无实现会话记忆）加载 egm-drift-report
        │                 只报不修：四类漂移 → 报告经 PR/评论回到 SPEC
        ▼
[操作者侧：裁决与归档（人在环）]
  偏差归因三类            实现更优 → 回写设计 ｜ 无伤大雅 → 记录接受 ｜ 设计被违反 → 立票修复
  归档                    plan doc 状态 / frontier 推进（feature-workflow 阶段 8）
```

**派单协议**：工单 issue 正文顶部放 `Part of #<SPEC>` + 设计文档相对链接；派单评论固定格式：

```sh
gh issue comment <N> --body "@jerry-jibu implement per SPEC #<SPEC> and docs/design/NN-<slug>-design.md — ticket <N> is frontier. Follow the Detailed Implementation Plan and its Verification Plan; TDD for each planned unit. The implementation-readiness report (linked in SPEC) is binding context."
```

worker 的 Executor 会读仓库 `AGENTS.md` 与 issue 全文，设计链接即授权范围。**bugfix 走 bugfix-workflow 短路径**：单票直接派单，无设计环节；风险高的 bugfix 收尾可加单轮 egm-review 抽查。

## 2.1 技能结合矩阵

**分流原则：需要人在环的技能留操作者侧；无人值守可完成的纪律进 worker。** 判定依据是 worker 的运行约束：无人环（`human_action` 只能问一个具体问题）、工单内自主、授权范围有限。

| 技能 | 归属 | 接入方式 |
|---|---|---|
| `grill-me` / `grill-with-docs` | 操作者侧 | 阶段 1 拷问（feature-workflow） |
| `egm-brainstorm` / `egm-draft` / `egm-review`（interactive） | 操作者侧 | 设计锁定，派单前置门 |
| `egm-resolve`（interactive breakdown） | 操作者侧 | auto-accept 变体才可进 worker |
| `to-spec` / `to-tickets` | **worker（元票）** | Approved 设计派一条元请求，worker 建 SPEC + DAG；人扫 DAG（约 30 秒） |
| `super-collect` | 操作者侧 | 供单源（阶段 0） |
| `egm-drift-report` | **worker（独立票）+ 人裁决** | fresh worker 保留金鱼性质，只报不修；归因三类留人 |
| `implement-spec` / `implement` / `tdd` / `code-review` 的**工程纪律** | **worker 内** | 三根绑定杆（下） |
| `egm-review` **uninterrupted 单轮抽查** | worker 内（P3 实验） | 等 P0 token 成本数据 |

**worker 进技能的三根绑定杆**（worker 经 rank-500 可见全部技能 + `skill` 工具按需加载 + 必读仓库 `AGENTS.md`）：

1. **派单协议（数据绑定）**：派单评论点名工作方式——引用的指令是数据，不改变授权，worker 照做（见上方模板 v2：Detailed Implementation Plan + Verification Plan + TDD）。
2. **仓库 `AGENTS.md`（环境绑定）**：目标仓库写"Executing agent tickets"节（读设计→TDD→跑 Verification Plan→安全自查→超范围 handback），所有票自动生效。
3. **团队节 / 团队技能（全局绑定）**：跨仓库稳定的工作方式进 prompts 团队节或 `dsh-superagent-<name>` 技能。

**减法**：worker 不原样加载 `/implement`——认领/建分支/回写机制 super-agent 编排层原生拥有（worktree、assignment、报告链路），重复会打架；worker 只取其纪律部分（TDD、小步提交、验证证据）。绑定杆 2 写纪律、不写机制。

**渠道内人机循环的边界**：单轮问答环原生支持——worker `human_action` 问一个具体问题到飞书话题/issue，人线程内回答（订阅扇出、唤醒优先槽），worker 自主恢复，不问 continue；grill 的"一次一个具体问题"哲学以此形态存活。但整套交互式技能（grill-me、egm-brainstorm 的多轮访谈）不进渠道：router 禁技术决策、worker 发言被 purpose gate + 100 词限制、每问一轮 = 一次阻塞报告（面板噪音 + 状态翻转），且评估门要求"方向已定 + 无待决设计决策"才接单——设计对话留在操作者侧，成品以设计链接进渠道。worker 也刻意排除了 `ask_user_question`（无人值守前提），这是分工不是缺失。

## 3. super-agent 侧的既有与待补

| 项 | 状态 |
|---|---|
| PR 安全自查门槛（injection / authz / secrets / deserialization / open-redirect） | ✅ 已写入 delivery 节（prompts Rev.2） |
| 不自动 merge、人工验收 | ✅ prompts Rev.1 |
| 飞书 bot 专属 CLI（`~/.local/bin/lark-bot`，bot-only strict mode） | ✅ 已配置并验证（11205 消除）；等 bot 入群后保存 feishu source |
| `dsh-superagent-identities` 团队技能（飞书用户 ↔ GitHub 账号映射） | ⏳ 等群成员 open_id（policy syncChat 同步后一次配成；skills 格式 `{name: body}`，注册加前缀 `dsh-superagent-`） |
| 项目级技能（rank 200 `<projectRoot>/.agents/skills`） | 视 agent-data-workspace 需要另行部署 |
| 工具调用层 guard | ❌ 见 §4 设计 |

## 4. guard 插件方案（工具调用层护栏）

### 4.1 扩展点

dsh 工具管线的 `tools/pre-execute` waterfall：监听者收到 `(exec, next)`，返回 `{ kind: 'deny', reason }` 即单调终否（`ctx.tools.guard()` 之上仍可叠加）。`exec` 携带 `agent` 身份，可用于只约束 worker 会话（router/主 Session 不受限）。

### 4.2 插件形态

一个 Cordis 插件（建议 `dsh-superagent-guards`，本地目录 `file:`/`link:` 引用），`inject: ['tools']`，`apply` 里对 `tools/pre-execute` 挂 waterfall 监听。挂载方式：`~/.dsh/profiles/superagent/cordis.patch.yml` 追加插件行 —— 与 `dsh-superagent` bundle 并列，不动上游包。

### 4.3 super-board guard → dsh 实现映射

| super-board guard | dsh 实现要点 | 备注 |
|---|---|---|
| guard-worktree-path | bash 命令参数中出现 `git worktree add` 时校验目标路径在 executor.directory 下 | worker 本就以 `$DSH_SUPERAGENT_DIR` 为 cwd |
| guard-secrets | `read`/`bash`（cat 等）目标路径命中 dotenv、`~/.ssh/`、credentials、`*.pem` → deny | 文件读取层，worker-gitconfig 只覆盖 git 凭据 |
| guard-key-literals | `write`/`edit` 内容正则（`AKIA…`、`sk-…`、`ghp_…` 等活密钥形态）→ deny + 提示改用环境变量 | 与 agents 仓库 `kv.ts` 键字面量纪律同思想 |
| guard-delete-outside | bash 中 `rm`/`find -delete`/`git clean` 的目标解析后越出工单目录 → deny | deny reason 给出可行动替代（在工单目录内操作） |
| guard-protected-push | `git push` 到 main/master 或非 `agent/` 前缀分支 → deny | 与"agent/ 分支前缀 + 人合并"策略闭环 |
| blocked commands | super-agent 原生 `executor.blockedCommands` | ✅ 已有，不重复实现 |

### 4.4 设计约束

- **deny reason 必须可行动**：worker 收到的是结构化拒绝，文案要说明"改用什么合法路径完成"——防止 worker 反复试错卡死（对应 super-agent 错误处理哲学：不绕过限制，报告阻塞）。
- **只挂 superagent profile**：操作者日常 profile 不装，避免误伤人的会话。
- **日志走 session 事件**：deny 进 `tools/execute` 前的 session log，面板的 worker 报告可见，便于调优。
- **先 observe 后 enforce**：与 super-agent `observe` 模式同哲学——第一版可将 guard 事件记日志不拒绝，观察一周误伤率后再切换。

### 4.5 工作量

插件本体 ~200 行 TS（纯监听 + 路径/正则判定，无外部依赖）+ 单测；风险在 bash 命令解析的边界情况（引号、子命令），首版只做保守匹配（宁可漏放不可误拦，漏放由环境层隔离与人工验收兜底）。

## 4.6 EGM on dsh：delegation 映射与验证状态

**决策：不新增 deepseek persona 文件。** 依据：

1. dsh 无命名 persona 注册表（ZCode/Claude/Antigravity 的 `agents/` 目录是文件扫描式注册；dsh 的 `subagent` 工具收 `description`+`name`+`prompt` 自由文本参数，`tool-subagent/src/index.ts:231`）——persona 文件没有部署落点（Stage 0 已删 `~/.deepseek/agents/` 死配置）。
2. EGM Delegation 抽象的第二类路径（spawn 通用子代理 + 先读 `agents/<file>.md`）对 dsh 完全适用，且每个 egm skill 目录自带全套 persona 拷贝，dsh worker 经 rank-500 加载技能后路径自闭合。
3. EGM 铁律 "No harness gets a fork of the skill text"——dsh 变体（persona 或 preset）都是 fork。

**delegation 映射**（供上游 harnesses.md 的 dsh 条目参考）：

| EGM 概念 | dsh 实现 |
|---|---|
| named persona spawn | 无 → 通用 `subagent` 工具，prompt 首句指示读取 skill 目录内 `agents/<persona>.md` |
| 金鱼只读约束 | 子代理 prompt 内声明 + 父会话不给写工具上下文（worker 预设本身写权限限工单目录） |
| synthesizer 并行 | `subagent` 多实例并行 + 父会话汇总（无独立 synthesizer 工具） |
| artifact-first | 子代理结果即文本返回，Elephant 落盘工作目录 markdown |
| headless 降级 | uninterrupted preset + resolve auto-accept（worker 无人环） |

**验证状态**：delegation 机制已确认（worker 预设含 delegation 组：`subagent-spawn-in-process` + control 工具，dump-config 实证）；"persona-first + 金鱼纯度"的模型行为验证归入 P0 首单观察——headless 独立验证被出厂策略挡住（credentials disabled + account 路由 destination 校验不放行，见 NOTES）。上游记录过宿主指令泄漏进评审员上下文的同类风险（harnesses.md issue #237），P0 时重点观察子代理是否收到 persona 之外的系统指令。



## 5. 落地路线

| 阶段 | 内容 | 前置 |
|---|---|---|
| P0 | 闭环人工跑通：挑一个小 feature 走完 操作者设计 → issue 派单 → worker PR → 人工 merge → drift-report；**顺带观察金鱼纯度**（worker spawn 的子代理是否收到 persona 之外的宿主指令） | ✅ 服务已就绪 |
| P1 | `dsh-superagent-identities` 技能；飞书 source 配置 | 飞书 bot |
| P2 | guard 插件 observe 版 → enforce 版 | 本设计评审通过 |
| P2 | frontier 派单器（cron/脚本：open + 无 blocker + 无 assignee 的新 frontier 票自动 @agent） | 首个 feature 的 DAG 验证后 |
| P3 | 评估 worker 收尾"单轮 egm-review 抽查（uninterrupted、headless 降级）"的成本收益；若采纳，作为 delivery 节可选条款 | P0 实测 token 成本数据 |

## 6. 风险与开放问题

- worker 并发 3 时 guard 的 exec.agent 判定需覆盖 subagent 树（worker 派生的子代理同受 guard）。
- 派单评论是 explicit 请求，Mandate 强度 explicit —— 设计文档本身不改变授权（引用的文档是数据不是规则）；设计约束的强制力来自验收与 drift 评审，而非授权系统。若要硬约束，应进 `executor.blockedCommands` 或 guard 插件，不靠提示词。
- egm 报告目前中英随会话语言；操作者侧评审用中文、worker PR 用英文（GitHub 消息已有语言约定），无需统一。
