# Feature 交付工作流（Feature Delivery Workflow）

> 适用范围：本项目所有新功能与能力演进。缺陷与回归走 [bugfix-workflow.md](bugfix-workflow.md)，两套流程共享门禁与合并纪律。
> 流程骨架自 agent-data-workspace 仓库 001 交付实战沉淀，门禁与路径已适配本仓库（Go 服务 + GPFS/EE 存储底座）。
> 技能映射：[`/grill-with-docs`](#阶段-1设计提案grill-with-docs) → [`/to-spec`](#阶段-2设计锁定to-spec) → [`/to-tickets`](#阶段-3工单拆分to-tickets) → [`/implement`](#阶段-5agent-领票实施)（内驱 `/tdd`）→ [`/code-review`](#阶段-7合并关闭与状态回写)。
> 配套文档：[issue-tracker.md](issue-tracker.md)（gh 命令与 native dependencies 约定）、[triage-labels.md](triage-labels.md)（标签词汇）、[bugfix-workflow.md](bugfix-workflow.md)（门禁/合并纪律，交叉引用不复制）。

## 核心原则：四段落盘，全程可溯源

Feature 的每个阶段产物都有持久归宿。任何人类或远程 agent 都能从原始提案出发，沿链接链追溯到已交付的设计、规格与实施记录：

| 阶段 | 产物 | 持久归宿 |
|---|---|---|
| 1 提案 | 原始输入与动机 | `docs/proposals/NNN-<slug>-proposal.md` |
| 2 设计 | 架构决策与领域术语 | `docs/design/NN-<slug>-design.md` + `docs/adr/NNNN-*.md` + `CONTEXT.md` |
| 3 规格 | SPEC issue（唯一契约） | GitHub issue |
| 4 实施 | 工单 DAG 与验收标准 | `docs/to-implement/NNN-<slug>.md` → 完成后 `docs/implemented/` |
| （缺陷） | 单票即记录 | GitHub issue 即唯一记录，**不建 docs 镜像目录** |

| 铁律 | 内容 |
|---|---|
| **GitHub Issue 唯一枢纽** | 与 bugfix 流程一致：一切关键信息以 comment 形式记入 issue，会话记忆视为未发生。 |
| **设计先于拆票** | 没有 design 文档（或明确的"走 bugfix 流程"判定）不得进入工单拆分——防止无设计直改架构。 |
| **DAG 双写一致** | GitHub **native dependencies**（blocked_by）是阻塞关系的唯一权威；`docs/to-implement` 的 mermaid 图是人读投影，两者不一致时以 GitHub 为准并修正投影。 |
| **状态回写义务** | 任何票状态变化，必须在**同一会话内**回写 plan doc 票状态与 README frontier 指针——文档滞后一个阶段即视为失职。 |
| **完成必须评审归档** | 全部工单关闭 ≠ 交付完成；必须通过 SPEC 级完成评审并归档（阶段 8），方案才算闭环。 |
| **破坏性操作必须决策** | 沿用 [bugfix-workflow 铁律](bugfix-workflow.md#核心原则github-issue-是协作的唯一枢纽)：共享测试环境上的重启/卸载/全量迁移跑等操作，issue 内声明影响面并等维护者决策。 |

---

## 总览

```
[1 设计提案] ──→ [2 设计锁定] ──→ [3 工单拆分] ──→ [4 实施方案落盘]
 docs/proposals/   SPEC issue      tickets +        docs/to-implement/
 → design/ADR      (design 锁定)   native deps      NNN-<slug>.md
                                                        │
[8 完成评审与归档] ←─ [7 合并关闭与状态回写] ←─ [6 PR 与 e2e] ←─ [5 agent 领票实施]
 docs/implemented/     (Closes #N +            (bugfix 阶段5纪律,   (frontier 认领,
 + SPEC 评审报告        plan doc 回写)          风险分层)            /implement+/tdd)
```

---

## 阶段 1：设计提案（/grill-with-docs）

- **提案落盘**：新想法先写 `docs/proposals/NNN-<slug>-proposal.md`（三位独立递增编号，README 见 [docs/proposals/](../../docs/proposals/README.md)）。内容至少包含：动机/问题陈述、期望效果（用户视角）、候选方案草案、影响面（模块/接口/存储格式）。
- **拷问与沉淀**：执行 `/grill-with-docs`（内驱 `/grilling` + `/domain-modeling`）。过程中敲定的架构决策沉淀为 **ADR**（`docs/adr/NNNN-<slug>.md`，四位递增），新术语进 `CONTEXT.md` 词汇表。
- **设计产出**：设计正文写入 `docs/design/NN-<slug>-design.md`（两位递增），并在提案头部回填 design 文档与 ADR 链接。
- **提案生命周期**（只翻状态，不移动不删除——提案是输入的原始记录）：
  `📝 草案` → `🔒 已受理`（SPEC 发布后，阶段 2）→ `✅ 已交付`（归档后，阶段 8）。

## 阶段 2：设计锁定（/to-spec）

- 执行 `/to-spec`：不重新访谈，把阶段 1 的会话上下文合成为 **SPEC issue** 并发布（模板：Problem Statement / Solution / User Stories / 测试切缝）。标题以 `SPEC: ` 开头，按 `/to-spec` 默认打 `ready-for-agent`。
- SPEC issue 是该 feature 的**唯一契约**：后续工单拆分、完成评审均以其为基准。
- 同步动作：design 文档状态行翻 `已锁定`；提案状态翻 `🔒 已受理` 并补 SPEC issue 链接。

## 阶段 3：工单拆分（/to-tickets)

- 执行 `/to-tickets`：按 **tracer-bullet 纵切**拆票——每张票打通全部层的窄路径、独立可验证、单上下文窗口可完成；宽重构走 expand–contract 序列。
- **阻塞关系用 GitHub native dependencies**：`gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`（完整约定见 [issue-tracker.md](issue-tracker.md) 的 Wayfinding operations 节）。不依赖正文文本行作为权威。
- 每张票：正文顶部 `Part of #<SPEC>`；标签 `ready-for-agent` + `area/<模块>` + `enhancement`；验收标准可勾选。
- 无前置依赖的票即 **frontier**。

## 阶段 4：实施方案落盘（docs/to-implement/NNN-<slug>.md）

把实施流持久化为 plan doc——远程/离线 agent 不进会话即可领票执行。**必选五件套**：

1. **头部定位块**：文档定位、SPEC 链接、ADR 链接、`CONTEXT.md` 术语锚点、当前状态行。
2. **架构红线（Guardrails）**：本 feature 特有的不可逾越约束（例：不破坏 `migrator.sh`/存量脚本契约、不绕开 etcd 权威源直写本地文件、磁带写期间禁止强杀进程、生命周期清理保证）。
3. **DAG 图（mermaid）**：与 native dependencies 一致的人读投影，frontier 票高亮；每票节点带状态标记。
4. **工单分解**：每票四要素——conventional-commit 风格标题、状态行（Blocked by …）、交付目标、可勾选验收标准。
5. **Agent Quickstart**：认领 → 分支 → TDD → PR → 回写状态的无上下文执行指引。

配套约定：

- **命名**：`NNN-<slug>.md`，三位独立递增。
- **README 活跃表**（`docs/to-implement/README.md`）：Plan ID | Title | SPEC | Tickets | Status | Frontier 六列；**frontier 列必须始终指向真实可领的票**。
- **状态词汇**：plan `🟢 Ready for Agent / 🔄 In Progress / ✅ COMPLETED`；ticket `🟢 Frontier / ⏳ Blocked / ✅ CLOSED`。

## 阶段 5：agent 领票实施

- **frontier 定义**：open + 无 open blocker（`issue_dependencies_summary.blocked_by`）+ 无 assignee，按 DAG 序取第一张。
- **认领**：`gh issue edit <n> --add-assignee @me` + comment（分支名 + 切片计划）——这是跨会话的占位声明。
- **执行**：`git checkout -b feat/issue-<N>-<slug>`；一个 issue 一个新会话；`/implement <issue 编号>` 内驱 `/tdd`，收尾 `/code-review`。
- **并行会话纪律、调试日志剥离、上下文卫生**：沿用 [bugfix-workflow 阶段 4](bugfix-workflow.md#阶段-4agent-实现)。
- **进度入 issue**：实现启动与完成各一条 comment（与 bugfix 同规）。

## 阶段 6：PR 与端到端验证

- **风险分层**：
  - 触碰 `pkg/watch`（Kafka watcher）、`pkg/pool`（迁移调度）、`pkg/client`（TMClient/JBFS/ES）、`migrator.sh`、`deploy/` 等运行路径的 feature → **必须**按 [bugfix-workflow 阶段 5](bugfix-workflow.md#阶段-5验证门禁) 在测试环境跑端到端门禁（本地全套测试 + 最小迁移冒烟、先窄后宽、结果入 issue）。
  - 纯文档 / CI 改动 → 本地 `go build ./... && go test ./pkg/...` + `make docs-check` 即可。
- 门禁结果（测试计数、失败分类、日志路径）comment 记入**被实施的 ticket issue**，作为跨会话对比依据。
- 红线：门禁导致共享测试环境重启/损坏 → 立即停跑、取证、issue 内声明并等维护者决策。

## 阶段 7：合并关闭与状态回写

- 提交信息：`feat(模块): 一句话（feat/issue-<N> 标题, Fixes #N）`；**PR 到 main**，合入自动关闭对应票。
- **Squash 合并约定**：一个 PR 压成一个 commit。PR 标题即 squash commit message（须符合 conventional 格式）；多工单 PR 的 `Fixes #N` 引用写入 **PR 正文**（合入自动关闭对应票）；分支内按票提交的历史不要求改写，票级溯源走 issue 评论链（commit 链接在关闭评论中保留）。
- 关闭评论四件套沿用 [bugfix-workflow 阶段 6](bugfix-workflow.md#阶段-6合并与关闭)：commit 链接、验证证据摘要、**遗留问题清单**（每条立新票并交叉链接）、回归资产清单。
- **回写义务**（合入后同一会话内完成）：
  1. plan doc 中该票状态 `✅ CLOSED`（含日期）；
  2. frontier 指针推进到下一张可领票（更新 DAG 高亮与 README 表）；
  3. 若 SPEC 全部票关闭，进入阶段 8。

## 阶段 8：完成评审与归档

1. **完成评审报告**：全部票关闭后，agent 通读 spec / design / 实施产物做整体 review，在 **SPEC issue** 发布报告：验收标准 vs 交付证据逐条对照、偏差说明、遗留缺陷清单（每条已立票——遗留缺陷不阻塞归档，但必须可追溯）。
2. **维护者 sign-off**：SPEC issue 评论确认。
3. **归档四步**：
   - plan doc 头部状态 `✅ COMPLETED` + 新增「完成总结」章节（交付表 / 关闭时间 / 已知后续事项）；
   - `docs/to-implement/README.md` 活跃表移除该行并指向归档；
   - `git mv docs/to-implement/NNN-*.md docs/implemented/`；
   - `docs/implemented/README.md` 归档表新增行。
4. 提案（`✅ 已交付`）、design、ADR、SPEC issue 全部**原地保留**，链接链不断——溯源不靠搬移靠链接。

---

## 快速命令参考

```bash
# 阶段 1：提案（先建文件再 grill）
$EDITOR docs/proposals/NNN-<slug>-proposal.md

# 阶段 2：SPEC issue
gh issue create --label "ready-for-agent,enhancement" --title "SPEC: ..." --body-file - << 'EOF'
## Problem Statement ...
EOF

# 阶段 3：native dependency（<db-id> 是 blocker 的数据库 id，不是 #号）
gh api repos/<owner>/<repo>/issues/<n> --jq .id   # 取 blocker-db-id
gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>

# 阶段 4/7：plan doc 状态回写（编辑文件随 PR 提交）
$EDITOR docs/to-implement/NNN-<slug>.md docs/to-implement/README.md

# 阶段 5：认领 frontier
gh issue list --state open --label ready-for-agent --json number,title,assignees
gh issue edit <n> --add-assignee @me
git checkout -b feat/issue-<N>-<slug>

# 阶段 6：门禁 → 见 bugfix-workflow 阶段 5 快速命令
# 阶段 8：归档
git mv docs/to-implement/NNN-<slug>.md docs/implemented/
```
