# Goldfish Annotated Review Report

**Target:** `docs/designs/multi-harness-agent-repo-governance.md` (1..380)
**Source:** critic_report.md（Stage 7 Round 1，三评审员收敛）
**Status:** resolved（2026-11-06：18 项 PROPOSE FIX + N 簇批量经 interactive breakdown 全部裁决——D1-D12 十二项用户裁决覆盖全部争议点后一次性应用于 TargetFile；1 项 DECLINE[HR 对称]维持不修；CONTEST 0 / ESCALATE 0）

## Prioritized Findings & AI Suggestions

### [B1] [design+structural+style 收敛] - Severity: Blocker
*   **Affected Scope:** CUJ 2 / C2 / C4 / CUJ 3 标题 / Stage 1 条目 7-8 / Alternative A / Problem 第 5 条
*   **Discrepancy Description:** 修订税则后旧路径与旧数字残留：`skills/vendor/<source>/**`、`skills/own/`、`own/ 或 vendor/`、`vendor+own`、条目 7/8 的旧流描述、"79 skills"、"3 个孤儿源"。
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** 验收契约与规范定义引用不存在的目录；实施数字过期（104 目录、5 源 7 条目 lock-only）。
*   ***Proposed Edit:***
    *   CUJ 2 Then → `仅 vendor/<owner>-<repo>/** 与 .skill-lock.json 变化；in-house/skills/ 与 vendor/unknown/ 零变化`；CUJ 3 标题 → `（in-house 数据流）`
    *   C2 → `目标存在于 in-house/skills/ 或 vendor/`；C4 → `repo（vendor + in-house 的 install-name 集）`
    *   Stage 1 条目 7：pull 目标 → `vendor/<owner>-<repo>/`；`永不触碰 own/` → `永不触碰 in-house/ 与 vendor/unknown/`；backup → `只收 in-house/skills/ 的 node 侧变更…`
    *   Stage 1 条目 8：`own/ 不入 lock` → `in-house/skills/ 不入 lock`
    *   Alternative A：`六源 × 79 skills` → `六源 × 104 个 skill 目录`
    *   Problem 第 5 条：`3 个 sources.conf 已删除的孤儿源条目` → `5 个 sources.conf 未声明源的 7 个 lock-only 条目`

### [B2] [design] - Severity: Blocker
*   **Affected Scope:** "不变部分"（L200 附近）/ CUJ 1 L61 / 目录树 sync-agents.sh 注释
*   **Discrepancy Description:** agents "四 harness deploy 保持现状"与部署矩阵"deepseek 无个人目录、死配置删除"互斥；`sync-agents.sh` 与 `sync-skills.sh agents` 两种说法并存；"生成"未定义。
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** 照办会复活冲突 C 的死配置；comprehension #4 同源。
*   ***Proposed Edit:*** "不变部分"改写为：链路 = `sync-skills.sh agents`（从各 skill 的 `agents/*.md` persona 生成 `~/.zcode/agents/`）→ `sync-agents.sh collect`（收进 repo `agents/`）→ `sync-agents.sh deploy`（**收敛为 zcode/claude/antigravity 三 harness，deepseek 目标移除**——dsh 无个人 agents 目录）；CUJ 1 L61 `L2 agents 部署到各 harness` → `L2 agents 部署到 zcode/claude/antigravity（实测各 10 条，与 repo agents/ 一致；deepseek 不适用）`。

### [B3] [design] - Severity: Blocker
*   **Affected Scope:** 三条同步流 / NFR 可恢复性 / C4 / lock v4
*   **Discrepancy Description:** 破坏性 guard 只覆盖 repo 工作树；node 侧 vendor 编辑与新写 in-house skill 会被 pull/restore `--delete` 无声抹掉。
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** archify 事故的行为模式（node 侧手改）实测存在；威胁模型必须闭合。
*   ***Proposed Edit:*** 三流规则与 NFR 增加：物化前置 **delta guard**——目标目录已存在时先比对内容（lock v4 增 `deployedHash` 或 dry-run diff），漂移非空即中止并列 diff 清单，人工裁决后才覆盖；guard 覆盖 pull/restore/doctor `--fix`；C4 增"内容漂移（vendor 区）"检查项。

### [M1] [design+structural+style] - Severity: Major
*   **Affected Scope:** lock v4 schema
*   **Discrepancy:** sources[] 短名 vs source owner-repo 两套命名；install-name 三形态；sourceUrl 丢失；扁平化歧义。
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Proposed Edit:*** schema 增顶层 `"sources": {"<owner>-<repo>": {"url": "…"}}` 注册段（覆盖 lock-only 冻结源）；条目 `source` 统一 owner-repo；install-name 唯一形态 = 对象键，删条目内 installName 字段（Stage 1 条目 8 同步改）；别名机制 = sources.conf 可选第 4 字段（缺省取目录名）；扁平化规则钉死 `owner-repo`（`/`→`-`，无嵌套）。

### [M2] [design+structural] - Severity: Major
*   **Affected Scope:** Problem 第 5 条 / Stage 1 条目 8
*   **Discrepancy:** orphaned 枚举漏 anthropics/GoogleChrome/mattpocock 三源；语义应为 "lock-only 冻结"。
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Proposed Edit:*** 条目 8 枚举补全 5 源 7 条目；`orphaned` 定义 = `lock-only 冻结（不在 sources.conf，含上游仍存的未声明源）`。

### [M3] [design] - Severity: Major
*   **AI Suggestion:*** PROPOSE FIX
*   ***Proposed Edit:*** G1 末尾加：`pull 仅在单一权威节点执行；其余节点只 consume（git pull + 物化），避免 vendor/lock 的跨节点合并冲突`（NG1 补一句呼应）。

### [M4] [design] - Severity: Major
*   **AI Suggestion:*** PROPOSE FIX
*   ***Proposed Edit:*** 三流规则 pull 条增三条声明：单源 clone 失败全中止（保持 die）；lock 写入 temp+rename 原子；中断重跑幂等收敛（单源 pull 二次执行无 diff 为验收）。

### [M5] [design+style] - Severity: Major
*   **AI Suggestion:*** PROPOSE FIX
*   ***Proposed Edit:*** unknown 区规则改：`冻结语义：勿手改、pull 永不触碰；条目记冻结日期，可经 adopt 通道复核——归编确认源 / 晋升 in-house / 删除退役`；G1 措辞 `勿手改镜像语义` → `冻结语义`。

### [M6] [structural+design] - Severity: Major
*   **AI Suggestion:*** PROPOSE FIX
*   ***Proposed Edit:*** 新增 `## Risks & Mitigations` 章节（置于 NFR 后）：供应链（上游 SKILL.md = 代理指令：上游 HEAD ≠ lock 锚时要求显式确认；pull 后人工 diff 为缓解；单人仓库风险自留）、多节点并发（M3 约束）、harness 行为漂移（M8 超期 warn）、lock/树漂移（M4 原子性 + C5）、MCP 配置备份安全（`harness/*/config/` 仅存 URL/command 类字段，**备份前剔除凭据类字段**，sideshow 现配置无凭据——实测）。

### [M7] [design] - Severity: Major
*   **AI Suggestion:*** PROPOSE FIX
*   ***Proposed Edit:*** CUJ 1 Given 补 `Node.js 运行时可用（sideshow 服务与 stdio MCP 依赖）`；Then L3 改 `MCP 配置写入**已验证** harness（zcode 必做；antigravity/deepseek 在各自路径验证完成前输出 unverified、不计入验收）`；L1 补 `（共享根 `~/.agents/skills`；per-harness 专属路径按期望态 manifest）`。

### [M8] [design] - Severity: Major
*   **AI Suggestion:*** PROPOSE FIX
*   ***Proposed Edit:*** G3/doctor 引擎加：`NOTES.md 验证日期超期（>90 天）输出 warn，提示重验`。

### [M9] [design] - Severity: Major
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Proposed Edit:*** C1 定级分区：`in-house=error（可修）；vendor/unknown=warn（镜像内容不可改，报告上游问题）`。

### [M10] [structural+design] - Severity: Major
*   **AI Suggestion:*** PROPOSE FIX
*   ***Proposed Edit:*** 归因矩阵更新：launch-video → `vendor/modem-dev-sideshow/`（上游实测），unknown 行 17→16 并从名单删除 launch-video，sideshow 行 1→2（sideshow、launch-video）；"39 matt"行注明 `（含 software-factory；resolving-merge-conflicts 属 lock-only，因上游已删）`；Stage 0 条目 2 补 `（实测 79 条；repo 104 vs node 79 差集由 C4 首次全量 restore 后收敛）`。

### [M11] [style+comp#3] - Severity: Major
*   **AI Suggestion:*** PROPOSE FIX
*   ***Proposed Edit:*** repair 白名单定稿四处对齐（G7/NFR/检查表后白名单段）：`symlink 去重/重建、部署缺口重部署（带 B3 delta guard）、lock 元数据补录`；**删除 G7 的"frontmatter 小修"**；C6 自动修复列改 `否（列举后人工确认删除）`。

### [M12] [style] - Severity: Major
*   **AI Suggestion:*** PROPOSE FIX
*   ***Proposed Edit:*** 冗余收敛：干净树规则定义收敛至 NFR，其余五处改引用（`（见 NFR 可恢复性 guard）`）；Problem"解法方向"段压缩为一句指引（`解法方向见 Goals G1-G8，一一对应`）；"in-house 不进 lock""第一公民""setup-matt 前置"各保留一处定义 + 引用。

### [M13] [structural+style] - Severity: Major
*   **AI Suggestion:*** PROPOSE FIX
*   ***Proposed Edit:*** restore 规则行改：`vendor/<owner>-<repo>/<name>/ 与 in-house/skills/<name>/ 统一物化到 ~/.agents/skills/<install-name>/（扁平）`。

### [M14] [structural+comp#14+design#16] - Severity: Major
*   **AI Suggestion:*** PROPOSE FIX
*   ***Proposed Edit:*** CUJ 5 槽位清单对齐 slot-map 九槽英文名并补 diagnose；CUJ 4 补 `Given: repo 与 node 处于同一部署态（doctor static 绿）`；G4 补一句：`install-name 全局唯一；in-house 与 vendor 同名时 in-house 胜出并提示；vendor↔vendor 同名才硬失败`。

### [M15] [design] - Severity: Major（已闭合，落一句）
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Proposed Edit:*** Alternative G 补：`实测 references 0.1MB/份 ×25 ≈ 2.5MB 上限，复制代价可忽略`。

### [N 簇] [style+structural+design] - Severity: Nit（批量，worth fixing）
*   ***AI Suggestion:*** PROPOSE FIX（下列各项）/ DECLINE（HR 对称性 F18）
*   ***Proposed Edit:***
    *   G1 删 `（2026-11-06 修订税则）`注记与"税则"字样，改"目录归属规则"；G1 长句拆 G1 目录规则 / G1 数据流权威 / G1 guard 三个子条
    *   "12 条 agents" → `10 条（实测 ~/.gemini/config/agents/ 与 repo 一致）`
    *   Alternative G 标签 → `Reason for Deferral`；各备选删 `Rejected by author:` 冗余前缀（保留于正文一句说明惯例）
    *   dsh 首现定义（Overview `deepseek-harness（下称 dsh）`）；全文 `节点/node` 统一为 `节点（node）`首现后用 `node`；`正文 prose`→`SKILL.md 正文`；`第三站备份镜像`展开半句；`守卫不变`→`沿用 lock v4 的跨源撞名硬失败（见下）`
    *   槽位内联枚举改两列小表（slot | 当前 skill）
    *   Q1/Q3 闭合记录的分支改子列表
    *   CALIBRATE：`近乎零成本`→`每次 pull 记一个 sha 的成本`；`极小的结构成本`→`引擎不随检查项增删而改动`；`已经历过大版本演进`→`存在改名先例`；`根治`→`规避`；`在路上`→`已列入计划`
    *   CUJ 2 Given `6 个源`→`6 个源（现有 4 + 新增 2）`
    *   "Drafting 期间已闭合"小节标题 → `Resolved During Drafting`，Open Questions 章名 → `Open Questions & Resolved`
    *   DECLINE：水平分割线对称性（无既有规则，纯审美）

## 统计

PROPOSE FIX 18 项（B1-B3、M1-M15）+ N 簇批量（除 1 项 DECLINE）；CONTEST 0；ESCALATE 0；DECLINE 1（HR 对称）。
