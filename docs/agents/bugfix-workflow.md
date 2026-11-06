# Bug 修复工作流（Bug-Fix Workflow）

> 适用范围：本项目所有缺陷与回归问题。流程骨架自 agent-data-workspace 仓库的交付实践沉淀，门禁与示例已适配本仓库（Go 服务 + GPFS/EE 存储底座）。
> 技能映射：[`/diagnosing-bugs`](#阶段-2根因分析) → issue → [`/implement`](#阶段-4agent-实现)（内驱 [`/tdd`](#阶段-4agent-实现)）→ [`/code-review`](#阶段-6合并与关闭)。
> 配套文档：[issue-tracker.md](issue-tracker.md)（gh 命令约定）、[triage-labels.md](triage-labels.md)（标签词汇）。

## 核心原则：GitHub Issue 是协作的唯一枢纽

**一切关键信息必须落在 issue 的 comment 里。** Agent 的会话上下文是易失的（跨会话即丢失），issue 及其评论是唯一持久的、可检索的、可链接的协作记录。任何人类或远程 agent 随时接管线程，靠的是评论链而不是某次会话的记忆。

| 铁律 | 内容 |
|---|---|
| **有迹可循** | 每个阶段结束，该阶段的关键产出**必须以 comment 形式记入 issue**（见下表）。只存在于会话或日志文件里的结论视为未发生。 |
| **证据先于理论** | 没有能让测试变红的复现（检测器/errno 表/失败日志行），不开修复 PR——`/diagnosing-bugs` 纪律。 |
| **破坏性操作必须决策** | 共享测试环境（带库/磁带驱动器、GPFS 集群、3 节点 etcd）上的重启、卸载、全量迁移跑：在 issue 里声明影响面并以选项形式等维护者决策；agent 不得自主执行。 |
| **副作用立即立票** | 修复过程中发现的每个新问题 → 独立 issue + 交叉链接回原 issue，不在原 issue 里堆叠。 |

**各阶段必须记入 issue comment 的内容**：

| 阶段 | 必须 comment 的内容 |
|---|---|
| 1 开 issue | 指纹/errno/复现序列/验收标准（issue 正文） |
| 2 根因分析 | 根因链（触发请求/事件 → 服务端状态 → 错误路径）、探针输出、外部系统日志指纹 |
| 3 方案决策 | 选项 ①②③ + 影响面 + 维护者的最终选择 |
| 4 实现 | 分支名、TDD 切片清单、阻塞点 |
| 5 验证门禁 | 门禁日志摘要、测试计数（pass/fail）、失败分类统计、日志文件路径 |
| 6 合并关闭 | commit 链接、验证证据、**遗留问题清单**（每条链接新 issue）、回归资产清单 |

---

## 总览

```
[0 取证] → [1 开 issue] → [2 根因分析] → [3 方案决策] → [4 agent 实现]
              (指纹入正文)   (根因链入评论)   (选项+决策入评论)  (进度入评论)
                                                                        ↓ (TDD red→green)
[7 回归资产沉淀] ← [6 合并关闭：收尾评论] ← [5 门禁验证：结果入评论] ←──┘
        ↓ (修复中发现新问题)
     [新 issue + 交叉链接] → 回到 [0]
```

---

## 阶段 0：问题发现与取证

发现问题的第一时间**只做取证，不做修复**。取证清单按问题类型：

| 类型 | 必须采集的证据 |
|---|---|
| 服务崩溃 / goroutine panic | panic stack 全文、`journalctl -u jibuarchival` 时间线、触发请求/事件序列、`last reboot` 时间点 |
| 迁移/磁带语义错误 | `migrator.sh` 失败行、`eeadm task list` / `eeadm migrate` 输出、GPFS `mmfslog` 相关行、涉事文件的 stub/resident 状态 |
| 数据一致性 | SQLite vs Elasticsearch vs TM API 三方对比（SQL dump + ES 查询 + `eeadm` 清单）、变更前后字节级 hash、操作时间线、并发度 |
| UI/回归 | Playwright 截图、viewport 尺寸、控制台错误 |

**红线**：如果问题在共享测试环境上复现会导致服务重启/磁带或数据损坏，**取证后立即停跑**，把影响面写进 issue，等维护者决策。

---

## 阶段 1：开 issue（取证结构化）

用 `gh issue create` + heredoc，**一个 bug 一个 issue**。issue 正文即第一份追踪记录，必须包含（模板）：

```markdown
## Parent
Part of #<父票或关联票>

## 现象（含指纹）
精确的错误行/errno/日志失败摘要。服务 panic 附 goroutine stack 指纹行
（如 `panic: runtime error: invalid memory address ... [recovered]`）。

## 复现
最小复现命令序列（能在测试沙箱/本机跑出的优先）。

## 根因假设（含置信度）
高/中/低分级；证据链引用（日志行号、SQL/ES 输出路径、探针输出）。

## 修复方向（可选，待讨论确认）
方案选项 + 推荐 + 理由。破坏性操作在此声明影响面。

## TDD 验收标准
- [ ] 每条可独立断言的验收项（含必须新增的回归测试名）
```

标签：`ready-for-agent`（规格完整时）+ `area/<模块>` + `bug|enhancement`。
破坏性/需基础设施配合的用 `ready-for-human`，并在正文顶部声明。

**副作用规则**：修复过程中发现的每一个新问题，**立即开独立 issue 并交叉链接**回原 issue（`See #N`），不在原 issue 里堆叠——这是副作用不丢失的保证。

---

## 阶段 2：根因分析

按成本递增的三层工具，**逐层升级、每层结论以 comment 记入 issue**：

1. **进程内探针**（首选，零风险）：在 `pkg/<模块>` 写临时检测器测试，断言不变量（例：对 `pkg/watch` 的事件处理写状态一致性检测器，对 `pkg/client/TMClient.go` 写契约断言）。让检测器变红 → 定位到具体分支。
2. **服务端插桩**：临时 `log.Printf`（前缀 `[xxxdbg]`）+ 本机构建复现（`go build ./...` + 本机配置运行或对接测试环境 REST）。取证后**必须删除**调试日志再提交。
3. **外部系统深水区**（EE / GPFS / 带库侧问题）：
   - EE 侧：`eeadm task list`、`eeadm tape list`、ITDT 诊断与状态字典——按 [reference/19 排障手册](../reference/19-ee-troubleshooting-itdt.md)逐项核对；
   - GPFS 侧：`mmhealth`、`mmfslog` 最新错误行、fileset/GPFS 存储池状态——按 [learning/gpfs](../learning/gpfs/README.md) 系列定位；
   - 产出写入 issue：出错帧、触发命令、关键状态字段（如 `require_replace`、`degraded`）的解读。

---

## 阶段 3：方案决策

- **非破坏性修复**（纯代码、测试内验证）：agent 可直接进入阶段 4。
- **破坏性/影响共享设施**（测试环境重启、带库/驱动器固件操作、全量迁移跑）：在 issue 里以 comment 列出选项（①②③）+ 推荐 + 各自影响面，**等维护者回复决策**。
- 决策后：维护者的选择留在评论链里；agent 追加一条 comment 同步最终方案摘要，进入阶段 4。

---

## 阶段 4：agent 实现

- **分支**：`fix/issue-<N>-<slug>`（从最新 main 切出）。
- **驱动**：`/implement <issue 编号>`（内驱 `/tdd`：每个切片先写失败测试再实现；`/code-review` 两轴审查收尾）。
- **上下文卫生**：一个 issue 一个新会话；会话过长先 `/handoff`。
- **回归测试要求**：修复必须附带**能在修复前变红**的回归测试。只修代码不加测试的 PR 不合。
- **调试日志**：提交前必须剥离临时 `[xxxdbg]` 日志。
- **并行会话纪律**：仓库可能有多会话并行。每次 `git add` 用显式路径（不用 `git add -A`）；提交前 `git status` 检查是否卷入他人文件；push 前发现 detached HEAD 立即 `git branch rescue-*` 救援。
- **进度入 issue**：实现启动时 comment 一条（分支名 + 切片计划）；完成时 comment 收尾（commit 链接 + 测试结果）。远程 agent 的会话结束后，这条评论就是下一个接手者的全部上下文。

---

## 阶段 5：验证门禁

**顺序执行，控制爆炸半径**。每轮门禁跑完，**结果必须 comment 记入 issue**（测试输出摘要、失败分类、日志路径、时间戳）——这是跨会话对比"这轮 vs 上轮"的唯一依据。

```bash
# 1) 构建 + 单元测试全套
go build ./... && go test ./pkg/... -count=1

# 2) 文档改动时补跑文档门禁（含链接、符号、mermaid、prose 四类）
make docs-check

# 3) 触碰迁移/带库路径时，在测试环境按 deploy/ 手册做最小冒烟：
#    单批 `migrator.sh` 迁移 + `curl /healthz` + 观察任务状态收敛，证据入 issue。
```

- **先窄后宽**：首次验证用 `-run <单测试>` 确认无 panic，再放宽到包级/全套。
- **失败收敛循环**：分析 → 修 → 重跑，直到核心集 0 失败。每轮的失败分类统计贴回 issue。
- **红线**：若验证导致共享测试环境重启/损坏，立即停跑、保留现场取证（日志、eeadm/ITDT 输出）、issue 内声明并等决策。

---

## 阶段 6：合并与关闭

- 提交信息格式：`fix(模块): 一句话（fix/issue-<N> 标题, issue #N）`，正文含根因、修复面、回归测试名，**必须含 `Closes #N`**（合入 main 自动关闭）。
- **Squash 合并约定**：一个 PR 压成一个 commit。PR 标题即 squash commit message（须符合上列 conventional 格式）；`Closes/Fixes #N` 引用写入 **PR 正文**（合入随 squash commit 关票）；分支内按切片的多提交历史不要求改写。
- 关闭前核对：全套 `go test ./pkg/...` 绿；issue 的 TDD 验收标准逐条勾选；无未剥离的调试代码；无卷入他人文件。
- **关闭评论（收尾记录）**必须包含：
  1. 修复 commit 链接；
  2. 验证证据摘要（门禁日志关键行 / 测试统计 / 前后对比）；
  3. **遗留问题清单**——每条链接到新开的 issue；
  4. 回归资产清单（本阶段 7 新增的测试/手册/基线，链接到文件）。

---

## 阶段 7：回归资产沉淀

每个修复周期结束后，把新防线固化进仓库并**在关闭评论中列出清单**，防止回归：

| 资产 | 位置 | 说明 |
|---|---|---|
| 不变量检测器 | `pkg/**/*_test.go` | 断言跨模块状态一致性的临时探针转正 |
| 契约/表驱动测试 | 同上 | `TMClient` 等外部客户端的响应映射测试 |
| 排障 SOP 更新 | `docs/reference/19-ee-troubleshooting-itdt.md` 等 | 新故障指纹与处置路径回写手册 |
| 部署/运维手册更新 | `deploy/` | 新发现的现网陷阱与规避步骤 |
| 策略样例 | `jbfs_policy_template/`、`policy.json` | 涉及策略行为的修复同步样例 |

沉淀检查（关闭评论需逐项回答）：
- [ ] 本次 bug 的复现路径是否已有测试长期守住？
- [ ] 是否有新的不变量值得写成检测器？
- [ ] 排障手册/部署手册是否需要更新？
- [ ] 策略样例是否需要刷新？

---

## 快速命令参考

```bash
# 开 issue（模板见阶段 1）
gh issue create --label "ready-for-agent,area/storage,bug" --title "..." --body-file - << 'EOF'
...
EOF

# 阶段产出记入 issue（跨会话跟踪的核心动作）
gh issue comment <N> --body-file - << 'EOF'
## <阶段> 产出
...
EOF

# 修复分支
git checkout -b fix/issue-<N>-<slug>

# 本地门禁：命令与最小冒烟步骤见「阶段 5：验证门禁」（不复制命令，防两处漂移）

# 已修 bug 溯源索引（issue 即唯一记录，不建 docs 镜像目录）
gh issue list --label bug --state closed --json number,title,closedAt \
  --jq 'sort_by(.closedAt) | .[] | "\(.closedAt[:10])  #\(.number)  \(.title)"'
```
