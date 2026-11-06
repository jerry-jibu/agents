# Stage 6 — Comprehension Test Report

* **Target:** `docs/designs/multi-harness-agent-repo-governance.md`（FeatureRange 1..258 / DetailedRange 259..362）
* **Reviewer:** egm-comprehension（Naive Reader，零机构知识；仅读文档本身，未读任何其他仓库文件；无 document standard）
* **Date:** 2026-11-06
* **说明:** 以下为评审员完整结果（转述 + findings 原文照录）。若作者认为某转述与意图不符，对应段落即存在表述缺口。

---

## 转述一：FeatureRange（第 1-258 行）——这个设计要解决什么问题、选择什么方案、放弃了什么

这份文档是对个人智能体环境仓库 `jerry-jibu/agents` 的治理重构设计。要解决的问题：仓库用一个扁平 `skills/` 同时扮演"上游镜像"（上游→repo）和"自研资产源头"（repo→部署）两个数据流方向相反的角色，产生七类已实测的缺陷——本地对镜像 skill（archify）的编辑会被 pull 的 `rsync --delete` 静默抹掉；ZCode 因双根读取（`~/.zcode/skills` 与 `~/.agents/skills`）导致每个 skill 重复注册；对 deepseek-harness 机制的错误猜测留下死配置（`~/.deepseek/agents/`）；自研 skill 的依赖只写在正文 prose 里且存在部署缺口；lock 文件（v3）有孤儿源条目且没有 commit 锚、锁不住上游版本；workflow 模板写死了外部项目（Go/GPFS/issue-tracker）的内容；新机 setup 没有分层定义与验收标准。

选择的方案：`skills/` 顶层双区分离——`vendor/<source>/<name>/`（pull-only 上游镜像）与 `own/<name>/`（自研，git 即版本）；git 仓库成为唯一权威，节点间靠 commit/push/pull 同步，再由脚本"物化"（复制）到机器上的扁平目录 `~/.agents/skills/`；四个 harness 各建 `harness/<name>/` 治理目录，以"已验证机制说明"（NOTES.md）为第一公民，未验证路径标 experimental；SKILL.md frontmatter 增加 `depends-on:` 显式声明依赖；`doctor.sh` 做"期望态对比"式健康检查（检查注册表带 severity 与 auto-repairable 元数据，修复分白名单自动与人工确认两级）；新机 bootstrap 分 L0-L4 五层由 `setup.sh` 驱动；workflow 模板通用化为占位符 + 能力槽位（slot）→ skill 映射表；接入 addyosmani 与 diagram-design 两个新上游源，历史同名目录用 adopt-or-diff（与上游 diff：干净则归编 vendor，有差异则作者裁决 drop 或 fork 进 own）处理。

放弃的：不做多机双向同步/冲突合并（repo 是单机为主的便携备份单元）；不做 skill 自动升级迁移工具（pull 即升级，版本追溯由 lock v4 的 commit 锚承担）；被明确否决的备选包括——vendor 用 git submodule（整仓粒度与按 skill 镜像不匹配）、repo 直接 symlink 作 live store（消灭防误改屏障）、维持扁平 + gitignore 排除 vendor（repo 不再是完整备份）、doctor 写成单体脚本、模板硬编码 mattpocock skill 名、harness 目录用点前缀命名；addyosmani references 的部署期路径改写被 Deferred 到未来（v1 接受复制策略）。

## 转述二：DetailedRange（第 259-362 行）——这个计划要动哪些文件、按什么顺序、怎么验收

计划按 Stage 0-3 分批推进，每 Stage 独立验收、失败可停在批次边界。Stage 0（当天止血、无结构变更）：`git restore` 回滚 `skills/archify/` 的本地编辑并在 node 侧重新物化；删除 `~/.zcode/skills/` 下全部 79 条 symlinks；删除 `~/.deepseek/agents/` 死配置目录；给 `skills/code-walk/SKILL.md` 的 frontmatter 加 `depends-on:` 并补部署缺口；新建 `harness/zcode/NOTES.md` 记录 Q1 结论。Stage 1（双区迁移与同步流改造）：`skills/` 顶层 `git mv` 重构，内部分三步（egm 源试点 → 其余三源 → own 三自研，无源归因目录暂留扁平区）；改造 `hack/sync-skills.sh`（pull 指向 vendor 并加工作树干净 guard、backup 限定收录范围、restore 分区物化、新增 `adopt` 子命令、跨源撞名硬失败）；lock v3 迁移到 v4；更新 README。Stage 2（per-harness 治理 + doctor + 新源）：创建四个 `harness/<name>/` 目录（NOTES.md + config/ 备份 + verify.sh 三件套）；创建 `hack/doctor.sh` 与 `hack/checks/c1..c8*.sh` 检查注册表；创建 `hack/setup.sh` 分层 bootstrap；`sources.conf` 追加两源并执行 adopt 归编；按验证结论修正 `sync-mcps.sh` 的写入路径。Stage 3（workflow 模板通用化）：feature/bugfix 两份模板改占位符、加前置条件块、技能引用改槽位引用、插入方案设计阶段与偏差评审阶段；新建 `docs/agents/slot-map.md` 作为槽位映射单一事实源。

验收（Verification Plan）：Stage 0 看 `git status` 干净、新 ZCode 会话 skill 无重复、`~/.deepseek/agents/` 不存在、dsh 会话可见 code-walk；Stage 1 看单源 pull 幂等（二次干净）、全量 restore 后 doctor static 全绿、lock v4 无未标注孤儿条目；Stage 2 用临时 HOME（`HOME=$(mktemp -d)`）模拟新机跑 `setup.sh` 到 L3 全过、doctor 零误报、`--live` 下 sideshow handshake 通过；Stage 3 看两模板可在无 Go/GPFS 上下文的新项目直接套用、C8 绿；回归红线是每个 Stage 收尾跑全量 doctor static + `sync-mcps.sh status`，与上一 Stage 基线对比无新增 error。

---

## Findings

（任务给出的候选词已逐一核对：adopt-or-diff（第 53、300 行两处均有流程定义）、slot/能力槽位（第 34、191 行）、孤儿条目/orphaned（第 22、170 行）可仅凭文档确定含义，frontmatter 为通用概念，不列为 finding；以下为确实无法自足读懂之处。）

1. [Major] 第 239、295 行 — "shared_dirs" 未定义。FeatureRange 仅在 Alternative G 出现一次（"v1 接受 shared_dirs 复制策略（egm 源已验证同构方案）"），DetailedRange 却用它作 Stage 1 排序的核心理由（"shared_dirs 最复杂、`sync-skills.sh agents` 生成链依赖它"）。它指什么（上游源中被多个 skill 共享、需随部署复制的目录，如 addyosmani 的 `references/`？）、复制机制如何工作、"egm 源已验证同构方案"指什么都不可知。猜测：sources.conf 第三字段声明的共享目录，部署时复制到每个相关 skill 旁。它承载了试点选择依据，读不懂就无法评估第一步为什么是 egm。

2. [Major] 第 139/159/170/300/305 行 — install-name 的派生规则与别名机制未定义。(a) install-name 是否恒等于 `vendor/<source>/<name>` 的叶子名 `<name>`，文档未明说；(b) 撞名时"提示手动指定别名"（第 170 行）、"提示别名的守卫"（第 53 行）——别名在哪儿配置（sources.conf？lock？命令行参数？）全文无配置面，实施撞名守卫时无法落地；(c) 第 159 行 schema 中 install-name 是 `skills` 映射的键，第 305 行却把 `installName` 列为条目内字段（"每条目 zone/source/commit/installName/pulledAt/orphaned"）——是键还是字段，两处不一致。

3. [Major] 第 36 行 vs 第 178 行（C1）vs 第 187 行 — frontmatter 修复归属三处矛盾。G7（第 36 行）说白名单自动修包含"frontmatter 小修"；doctor 检查表中唯一的 frontmatter 检查 C1 的"自动修复"列为"否（报告）"；第 187 行的白名单清单（C2/C3/C4 的重部署与去重、C6 列举）也不含 frontmatter。frontmatter 到底能否自动修，无法判定。

4. [Major] 第 108 行 vs 第 195 行 vs 第 295 行 — agents 生成-采集-部署链的脚本归属与部署目标矛盾。目录树列出独立脚本 `hack/sync-agents.sh`（"流程不变（collect → deploy 四 harness）"），但"不变部分"（第 195 行）与 Stage 1 试点验收（第 295 行 "`agents` 子命令链路正常"）都把该链归于 `sync-skills.sh agents` 子命令——是同一入口的两种叫法还是两条并行链？且"四 harness deploy"与部署矩阵"deepseek 无个人 agents 目录（运行时委托）、`~/.deepseek/agents/` 死配置删除"（第 148 行、Stage 0 第 3 项）冲突：agents 链对 deepseek 部署到哪里？"生成"一步（10 个 egm-*.md 从何生成）也从未说明。Stage 1 第一步的验收标准依赖这条链，验收什么无法确定。

5. [Major] 第 295 行 vs 第 332 行 — "其他"目录的归宿不闭合。Stage 1 说"其余无源归因目录（25 个 addyosmani 命名 + diagram-design + 其他）暂留扁平区，Stage 2 adopt-or-diff 归编"，但 Stage 2 第 13 项只归编"25 个 addyosmani 命名目录与 diagram-design"——"其他"是多少个、是什么、最终进 vendor/own/删除还是永久留在扁平区，全文无交代；而 C4/C5 与 lock v4 的一致性检查都要求 repo 与 lock 一一对应，这些目录的未定义状态会直接撞上验收。属两个 Range 之间的矛盾。

6. [Major] 第 268 行 — Stage 0 第 1 项两侧清理范围不一致（破坏性操作）。repo 侧是 `git restore skills/archify/`（单一路径），node 侧是"重新物化 `~/.agents/skills/archify*`（覆盖带本地编辑的副本）"（通配符）。若 archify 是一族目录（vendor 源列表第 93-94 行把 archify 列为一"源"，暗示其下多个 skill），repo 侧 restore 覆盖不到兄弟目录，"两处同步清，防 backup 流把残留带回"就不成立。猜测：本意是 `git restore 'skills/archify*'` 或应列出确切目录清单。

7. [Major] 第 359、362 行 vs 第 319 行（第 11 项，Stage 2）— 验收时序矛盾。Stage 1 验收要求"全量 restore 后 doctor static 全绿"，回归红线要求"每个 Stage 收尾跑一次全量 doctor static"，但 `doctor.sh` 与 `checks/` 到 Stage 2 才创建（Create ×9）。Stage 0/1 收尾时 doctor 不存在，与"失败可停在批次边界"的批次独立性矛盾。猜测：要么 Stage 1 验收延后补跑，要么 doctor 应提前到 Stage 1 交付。

8. [Nit] 第 20 行起 — "dsh" 缩写首次出现未展开。需从 Overview 的 "deepseek-harness" 与第 148 行 "dsh 会话" 自行拼合出 dsh = deepseek-harness。猜测即此；应写明一次。

9. [Nit] 第 131、252 行 — "rank 500" / "rank 200" 未定义。rank 是什么量纲、数值方向（越大越优先还是越小越优先）、由谁的机制定义，均不可知。猜测：dsh 对 skills 发现根的优先级权重（用户级 500、项目级 200）。它支撑"dsh 零部署是期望态"论断及 Future Improvements 的项目级部署，应一句话定义。

10. [Nit] 第 35、106、332 行 — sources.conf 管道分隔格式的字段语义未说明。从两条例子可猜 field1 = git URL、field2 = 上游内 skills 子路径、field3 = 共享目录名（空 = 无），但"标准自含形态"（第 35 行）等描述默认读者已懂该格式；"现有格式即可"（第 106 行）把定义外包给了仓库里的现存文件。应附一行格式说明。

11. [Nit] 第 30/31/67/126 行等 — "物化"未显式定义。可从数据流图（第 126 行"物化工作树，非权威"）与 Alternative B（"物理上分离……由物化脚本衔接"）推出 = 从 repo 实体复制到 node 目录（非 symlink），但建议首次出现时钉死"复制而非链接"。

12. [Nit] 第 52 行 vs 第 145 行 — zcode MCP 双路径关系未说明。Q1 结论提到"MCP 另有 `~/.agents/mcp.json` fallback"，部署矩阵给的是 `~/.zcode/cli/config.json` → `mcp.servers`。两者是 primary + fallback 还是并列、谁覆盖谁，未说明；影响 `harness/zcode/config/` 备份什么与 `sync-mcps.sh` 写哪里。

13. [Nit] 第 97 行 vs 第 147 行 — 数量不一致：`agents/` "现有 10 个 egm-*.md"，antigravity "已写入 12 条"。多出的 2 条是什么未解释。

14. [Nit] 第 84 行 vs 第 191/354 行 — CUJ5 的槽位清单用中文且仅 8 项（grill/方案设计/spec/tickets/implement/tdd/code-review/偏差评审），slot-map 用英文 9 项（含 review/drift/diagnose）。映射靠猜（方案设计=design、code-review=review、偏差评审=drift），diagnose 在 CUJ5 缺席；"全链路槽位均有指向"验收时以哪份清单为准有歧义。

15. [Nit] 第 12 行 — "node 状态的第三站备份镜像"隐喻未解释。猜测：上游(1)→node live 目录(2)→repo 仅作第三处被动备份(3)，即 repo 当前无治理职能。应展开。

16. [Nit] 第 6 行 — "EGM" 缩写未展开，与 egm 源、egm-* skills 的关系（可猜 egm 源即该方法论的 skill 集）也未写明。

17. [Nit] 第 48/61/98/195/360 行 — sideshow 服务是什么未介绍。可猜是本 repo 管理的唯一 MCP 服务（`mcps/sideshow.json`），并被用作 MCP 链路通断的验收哨兵（"看 sideshow 工具是否出现""handshake 通过"），但它提供什么、为何选它做 handshake 验收对象，文档未说。

18. [Nit] 第 239 行 — "上游 #361 的断链问题"引用外部 issue 编号，无链接无上下文（哪个仓库、断链指什么），读者无法核验。

19. [Nit] 第 73 行、第 283 行 — "部署命令"未指明具体命令。CUJ3 "编辑后运行部署命令"、Stage 0 第 4 项 "随后部署 skills/code-walk/ → ~/.agents/skills/code-walk/"——文档定义的 restore 是全量物化，没有单 skill 部署命令。猜测：跑 `sync-skills.sh restore` 或手工复制单目录；应写明。

20. [Nit] 第 317 行 — Stage 2 第 10 项标注 "Create ×4" 含 zcode，但 `harness/zcode/NOTES.md` 已在 Stage 0 第 5 项创建（"该目录的第一块内容"）。Stage 2 对 zcode 实际是补 config/ 与 verify.sh，应为 Create ×3 + 扩展 ×1，否则实施者可能重复建目录。

21. [Nit] 第 295 行 — 第 6 项声称"每步独立验收"，但只给了第一步（egm 试点）的验收标准；第二步（其余三源）、第三步（own 三自研）的验收标准缺失。

22. [Nit] 第 322 行 — doctor 的"期望态清单"载体未定义：是独立文件（路径、格式？）还是内嵌？"初版 = 部署矩阵的机器可读化"给了来源没给存放形式；`checks/*.sh` 的"元数据头"（severity/auto-repairable）具体声明格式（脚本注释约定？）也未给，实施第 11 项需自行发明约定。

23. [Nit] 第 37、327 行 — L4 "workflow 模板就位/文档投放"的具体动作未定义：模板本就随 repo 存在于 `docs/agents/`，且 Future Improvements 明说"当前仅 docs/ 存档 + 手动套用"——setup.sh 在 L4 到底做什么（复制到某处？仅校验？）不清楚。

24. [Nit] 第 332 行 — 第 13 项内步骤顺序歧义："执行 adopt 对 25 个……归编；pull 两新源"。adopt 需先有上游参照（depth-1 clone）才能 diff，句子却把 pull 放在 adopt 之后。猜测：adopt 自行临时 clone 上游做 diff，pull 是归编后的首次正式拉取；应写明 adopt 的上游参照来源。

25. [Nit] 第 344、349 行 — Stage 3 以现有模板的既有阶段名（"阶段 1 设计提案""阶段 2 设计锁定""阶段 7 合并""阶段 3 方案决策""阶段 6 合并关闭"）定位插入点，但本文档未复述现有模板结构，读者必须打开 `docs/agents/*.md` 才能核对——属对外部文件内容的硬依赖，文档自身无法验证插入位置。

26. [Nit] 第 358 行 — Stage 0 验收未覆盖第 5 项（`harness/zcode/NOTES.md` 的创建无对应验收条目）。

---

以上为可懂性测试结果；转述一、转述二即使存在偏差本身也是发现——若作者认为某转述与意图不符，对应段落即存在表述缺口。未做方案优劣评价。
