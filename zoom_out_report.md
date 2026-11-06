# Stage 5 — Initial Zoom Out Review Report

* **Target:** `docs/designs/multi-harness-agent-repo-governance.md`（全文 362 行）
* **Reviewers:** egm-zoom-out、egm-inventive-catalyst（并行 fresh-context）
* **Standard:** `zoom-out-standard.md`
* **GoldfishContext:** concepts_brief.md、hack/sync-skills.sh、hack/sources.conf、.skill-lock.json、README.md
* **Date:** 2026-11-06
* **事实核验:** 本会话已独立复核——repo 实测 **104** 个 SKILL.md 目录（设计口径 79 过期）；weather/smell/prd/ship-it/review-it/modern-go 抽查在 lock 中均 0 条目。

## 发现汇总

统计：🔴 Blocker ×1（双评审独立收敛）、🟡 Major ×7、🟢 Nit ×8。

### F1 [🔴 Blocker] backup 流保留 own 的 node→repo 通道，与"repo 唯一权威"自相矛盾（双评审收敛）

* **定位:** 数据流模型图（L118-139）、G1（L30）、Stage 1 #7b（L300）
* **矛盾:** 设计声明"node 是物化工作树，非权威、own 的编辑发生在 repo"，却让 backup"只收 own/ 的 node 侧变更"——后者只在 node 上存在 own 编辑时才有意义，即同时声明 node 非权威与 node 是 own 合法作者来源。现有 `cmd_backup` 是 additive rsync、无 diff 呈现，node 旧文件会静默覆盖 repo 已提交内容：冲突 A 的机制在 own 区复活，只是范围缩小。
* **补救（两位评审员方案收敛后）:** skills 的 backup 收集语义取消。own 区 node 侧漂移由 doctor C4 报告、人工裁决（或经显式 `adopt` 子命令 diff 呈现后落盘）；backup 仅保留真正 node 起源的产物收集（`agents/`、`mcps/`、`harness/*/config/`——这些只能在 node 侧生成，属生成管线而非双权威）。README 声明唯一作者位置约定。

### F2 [🟡 Major] 归因账目与库存对不上：104 目录 vs 79 口径，16+ 无主目录

* **定位:** Stage 1 #6（L295）、Q3 处置（L53）、lock v4（L155-170）
* **发现:** 实测 104 个含 SKILL.md 目录。至少 16 个（weather、smell、prd、prd-to-spec、to-design、ship-it、review-it、loop-it、note-it、quick-go/quick-learn、modern-go、insight-diagram、graph、explain-diff-html、software-factory、test-value、simplify-codebase、launch-video、refactor 等）不在 lock、不属 6 源、不是 own（已验证）；另有 lock 有源但源不在 sources.conf 的目录（skill-creator←anthropics/skills、modern-web-guidance←GoogleChrome、find-skills 等）。这些目录在 `vendor/<source>/` 无落点，adopt 的 diff 上游也不存在。Q3 的"交集 = 25 个同名"与树现状不符（25 只覆盖 addyosmani 命名子集）。
* **补救:** Stage 1 开工前先产出全量归因清单（104 目录逐一标注 vendor 源 / own / 待裁决，封闭名单）；无上游可 diff 的目录直接 `git mv` 冻结进 `vendor/<来源名>/`——vendor 语义放宽为"勿手改的镜像"，不必以 sources.conf 有该源为前提。

### F3 [🟡 Major] 检查注册表是为预测性膨胀建造的前置基础设施（YAGNI）

* **定位:** G7（L36）、Alternative D（L219-221）、Stage 2 #11（L322）
* **发现:** `hack/checks/*.sh` ×8 + 元数据协议 + 引擎遍历，服务当前仅 8 项检查；"检查项必然膨胀"是预测不是实测瓶颈。bash 单文件函数表 + 关联数组即可等价获得可增删性与 repair 分级。
* **补救:** doctor v1 单文件交付（函数即注册表，含 C1-C8 与 `--fix` 白名单）；检查超约 15 项或出现第二个消费者时再拆目录。

### F4 [🟡 Major] slot→skill 映射表是给两份个人文档建的间接层（YAGNI）

* **定位:** G5（L34）、Stage 3 #17（L351-354）、C8（L189-191）
* **发现:** 2 份模板 ×grep/sed 的修复成本与"只改一张表"完全相同；间接层净代价 = 模板不可直读 + 一份元数据 + 一项检查。此机制承自 concepts_brief 异议 #10 裁决，但其前提在 2 文档量级下不成立——**注意：这挑战的是已裁决项，需作者确认**。
* **补救:** v1 模板直接写 skill 名 + 头部一句"上游改名请全局替换"；slot-map.md 与 C8 推迟。

### F5 [🟡 Major] 同一期望态信息存在三处表达，违反自设"只存一处"原则（双评审收敛）

* **定位:** G3（L32）、部署矩阵（L143-150）、Stage 2 #10/#11、C7
* **发现:** 每 harness 三件套（NOTES.md + config/ + verify.sh）+ doctor 期望态清单 + C7 live 检查 = 三套机制描述同一问题；verify.sh 与 doctor --live 是两套会各自腐化的断言源。
* **补救:** 收敛两层——每 harness 一份 NOTES.md（人读机制说明，链接机器可读期望态 manifest，manifest 为 SSOT）；verify.sh 取消，断言并入 doctor --live；设计文档中的矩阵表标注"示意，以 manifest 为准"。

### F6 [🟡 Major] addyosmani 正式化捆绑引入三个组件，收益只是出处归编（挑战用户既定决策 G6）

* **定位:** G6（L35）、Stage 2 #13（L329-332）、Alternative G（L235-239）
* **发现:** 接为 pull 源拖进 adopt 常驻子命令 + references 复制放大（25 skill × 整棵树）+ 永久漂移检查，而这 25+ 目录已存在已能用——成本收益倒挂。
* **补救:** 与 F2 合并处理——目录 `git mv` 进 `vendor/addyosmani/` 冻结即完成归编；sources.conf 接入与 references 复制推迟到真实出现"要从该上游拉更新"的需求。**此项需作者裁决（与 G6 决策冲突）。**

### F7 [🟡 Major] repair 覆盖保护不对称：repo 侧有 guard，node 侧只有政策

* **定位:** G7 repair 分级（L187、L248）、C2/C4（L179-181）
* **矛盾:** "任何覆盖 node 本地改动的操作"列人工确认级，但 C2/C4 的"重部署"标白名单自动修——重部署本身就是覆盖 node 目录的操作，白名单与受保护类直接相交。靠"幂等"假设兜底不是机制。
* **补救（预补偿）:** 自动修复前置 delta guard——目标 node 目录与 repo 当前版本（或 lock 记录的部署态 hash）无 delta 才允许自动重部署，有 delta 自动降级人工确认；同一 guard 内嵌到 pull/restore 的 rsync 之前（检测到 delta 先隔离转存再覆盖）。

### F8 [🟢 Nit] references 复制放大可用"repo 单份 + 物化期展开"消除

repo 内 `skills/vendor/addyosmani/_shared/references/` 单份存储，deploy 物化时展开进各 skill 目录——与既有"repo 分区 → node 扁平"是同一变换原则；漂移检查退化为单树比对，pull diff 信噪恢复。（若 F6 裁决推迟接源，此项随之推迟。）

### F9 [🟢 Nit] fork 进 own 后与上游静默失联

建议 fork 时记 `forked-from: <source>@<commit>` frontmatter + doctor warn 级"fork 基点落后于该源最新 commit 锚"。不做完整 patch-overlay（YAGNI）。

### F10 [🟢 Nit] `teach` 依赖无正文证据

code-walk 正文实测仅提 archify/diagram-design（L33），无 teach。设计三处写死三依赖（Stage 0 #4 已 hedge）——上游叙述同样待复核。

### F11 [🟢 Nit] lock 孤儿条目直接删除

git 历史本身即 provenance；死条目保留 `orphaned: true` 反而给 C5 增加标注正确性检查义务。

### F12 [🟢 Nit] bootstrap L4 近乎 no-op

模板在 repo docs/ 内，clone 即得；五层可并四层（或 L4 改为"doctor 全绿"终检）。

### F13 [🟢 Nit] C4/C7 与现有脚本职责重叠

C4 vs `sync-agents.sh list`、C7 vs `sync-mcps.sh status`——需声明吸收/退役关系，否则两套部署状态事实源。

### F14 [🟢 Nit] Non-Goals"单机为主"与通篇多节点操作模型措辞矛盾

改为"无自动同步协议；多节点经 git 手工纪律（commit/push/pull）协调"。

### F15 [🟢 Nit] commands 双根机制已验证却留白检查

zcode commands 与 skills 同构双根（`~/.zcode/commands` / `~/.agents/commands`）+ `~/.agents/mcp.json` fallback 已记入 Q1 结论但只进 NOTES 不进检查——重复注册类 bug 在 commands 面未覆盖。一次会话实测后决定 C3 是否泛化。

### F16 [🟢 Nit] claude/antigravity skills 部署优先 symlink 单发现版

若验证结论为"只读自有路径"，优先 symlink 到 `~/.agents/skills` 条目（zcode 的问题是双根重复，不是 symlink 本身）；symlink 发现行为未验证前不写死。

## 通过项（双评审一致）

* 根因聚焦：7 问题→解法映射完整；vendor/own 直击冲突 A 病根。
* Non-Goals 判断正确（submodule、双向同步、gitignore 否决理由均成立）。
* git 作为恢复机制（干净树 guard 机制化）是正确的"用已有机制替代自建"。
* egm 试点先行 + 每批独立验收，大爆炸风险控制正确。
* 未验证路径标 experimental/unverified 且不计退出码，防止猜测固化为规则。
* Stage 0 五项止血可直接执行、不依赖后续结构。
* 双区矛盾与扁平部署矛盾已被正当消除（inventive-catalyst 确认无假折中）。

## 更简单的整体形态（zoom-out 提案，供 F3/F4/F5/F6 裁决参考）

Stage 0 照做 + 双区 + pull 只写 vendor + 干净树 guard（防误改/可恢复）+ setup.sh = restore/deploy/configure 串联收尾跑单文件 doctor（快速导入）。可删除或降级：skills backup 流（F1）、checks/ 注册表（F3）、slot-map+C8（F4）、verify.sh（F5）、adopt 常驻化（F6）、lock orphan 簿记（F11）。约砍掉设计近一半新增结构，三件核心诉求不缺。

## 总体判断

骨架成立：双区 + git 权威 + 期望态 doctor 是满足防误改/可恢复/快速导入的最小正确形态。最薄弱一环是 F1（backup-own 通道让要消灭的双向数据流在 own 区合法存活），其次是 F2（归因账目对不上库存，Stage 1 第一批 git mv 就会暴露无落点目录）。骨架之上叠了约一倍可拆组件（F3-F6），复杂度与单人仓库规模不成正比——其中 F4/F6 挑战的是已裁决项，需作者重新裁决。
