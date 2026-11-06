# Stage 9 — Implementation Readiness Report（Rev.3 DetailedRange 291..391）

* **Reviewers:** egm-implementation-readiness、egm-codebase-details（逐行实测核对）、egm-style
* **Standard:** implementation-readiness-standard（零决策规则 / 文件边界 / 可机械验收）
* **Date:** 2026-11-06
* **Status:** resolved（R1/R2/S1-S9 + Nit 批量已全部应用于 Rev.4；条目重编号 1-18 连续，执行序与验收判据落定）
* **结论（三评审员一致）：不能直接开工**——两个 🔴 为"执行即失败"级；现状事实核对基本全数通过（104/39/25/7/3/2/1/4/16 算术闭合、文件清单对象全部现存、C1-C7 均有落点），缺陷集中在**计划与现有脚本机制的衔接**。

## Blockers

### R1 [🔴×2 收敛] Stage 0 自我回退：条目 4 的 restore 尾钩复活条目 2/3 的清理

`cmd_restore`（sync-skills.sh:106-124）末尾无条件调 `ensure_dir_links`（重建全部 79 条 `~/.zcode/skills` symlinks）与 `cmd_agents`（→ `sync-agents.sh deploy all`，HARNESSES 含 deepseek → 重铺 `~/.deepseek/agents/`）。按条目编号顺序执行 2→3→4，Stage 0 验收（无重复、死配置不存在）必然失败。条目 1 的"node 侧重新物化"同理。
**修复**：Stage 0 写死执行序——条目 4（及一切 restore/pull/agents 类操作）**先于**条目 2/3；并加禁令"条目 7 完成前禁止再跑旧 pull/restore/snapshot/agents"；条目 4 改用直连 rsync 物化绕开尾钩（首选）。

### R2 [🔴×2 收敛] `hack/sync-agents.sh` 缺席变更清单；"agents deploy 收敛三 harness"错挂在条目 15（sync-mcps.sh）名下

FeatureRange 承诺的"deepseek 目标移除"与"`list` 降级为 doctor 格式化视图"均为 sync-agents.sh 的 Modify，但条目 1-17 无此条目——执行者按清单跑必漏改，且每次 agents deploy 静默复活死配置（C1-C7 无一检查 `~/.deepseek/agents`）。
**修复**：新增独立条目"hack/sync-agents.sh（Modify）"：HARNESSES 删 deepseek 行与 `DEEPSEEK_AGENTS_DIR` 覆盖变量、usage 同步、`cmd_list` 改消费 doctor 输出；条目 15 删去 agents 字样。

## Majors

*   **S1 条目 6/7/8 交织未声明**：egm 试点验收（6 第一步）前提是 7(a) pull 改写 + 8 lock schema 已落地；按编号顺序执行在 6-第一步-验收卡死。修复：显式顺序——先落 7(a)/(c) 骨架与 8 schema → 再跑 6 三步，验收挂切片。
*   **S2 vendor 内层布局未定义**（嵌套保留 vs 扁平）：决定 rsync 目标、restore 反查算法、C5 遍历。修复：钉死 `vendor/github.com/<owner>/<repo>/<install-name>/` 扁平（pull 时折叠上游分类目录）；restore 反查 = lock 键（install-name）→ vendor 路径由 source + 键拼接。
*   **S3 lock 覆盖时序 + 初值**：25 addyosmani + diagram-design 在 Stage 1 入 vendor，源到条目 14 才进 sources.conf——C5（条目 12 先跑）判 26 个杂散；commit/pulledAt/deployedHash 初值无规定。修复：条目 8 即在 lock sources 段登记两新源（条目 14 仅改 sources.conf + adopt）；初值 = commit 取归因 depth-1 clone 的 HEAD、pulledAt = 迁移日、deployedHash = 首次全量 restore 后回填；Stage 2 头部注明执行序（14 先于 12 的 C5 终检）。
*   **S4 部署集与 unknown 物化未定义**：Stage 1 验收"doctor static 全绿"隐含 node 已 104 对齐，但 unknown/未 adopt 的 addyosmani 是否物化没说（行 335 vs 389 口径错位）。修复：钉死部署集 = vendor 全部（含 unknown、含未复核 addyosmani）+ in-house，首次全量 restore 对齐 104；行 389 改为可数判据（临时 HOME `~/.agents/skills` 条目数 = 104）。
*   **S5 collect 职责切分 + 旧机制拆除**：agents/ 收集双归属（sync-skills collect vs sync-agents collect + `cmd_agents` 自动尾钩）；`ensure_dir_links`/`ZCODE_SKILLS`/`[link]` 标记不拆则 C3 与 restore 互锁；`snapshot` 子命令去留未声明。修复：条目 7 增补 (g) 移除 ensure_dir_links/ZCODE_SKILLS/[link]（cmd_pull/cmd_snapshot/cmd_restore 三处调用点同拆）；(h) collect 职责切分——agents/ 归 sync-agents collect，sync-skills collect 只收 mcps/ 与 harness config；`cmd_agents` 的自动 collect+deploy 尾钩改为仅生成不部署；(i) `snapshot` 删除（commit 语义并入 collect 后的人工 git 提交流程）。
*   **S6 R-M-C 的 C5 豁免无载体**：冻结登记只有源级（sources 段 frozen）与 unknown 区（FROZEN.md）；R-M-C 在活动源目录下，两个载体都盖不到 → C5 恒误报。修复：活动源下的上游已删遗留条目以 `vendor/github.com/<owner>/<repo>/FROZEN.md`（与 unknown 区同构格式）登记；C5 断言的"frozen 登记"数据源 = sources 段 frozen 标志 + 各 FROZEN.md。
*   **S7 expected.json 无 schema**：附与部署矩阵 4 行对应的样例（skills 期望/agents 期望/mcp 期望/verifiedAt/unverified 表示法）。
*   **S8 deployedHash 算法未定义**：钉死 `find <dir> -type f ! -name .DS_Store -print0 | sort -z | xargs -0 shasum | shasum`（doctor/restore/pull 共用函数，跨节点可比）。
*   **S9 Stage 0 回滚范围外推**（style）：archify-review/tuning"一并入清单"超出用户 drop 裁决范围。修复：改为"若有脏改动 → 逐目录经作者确认后处置（不自动外推 drop）"。

## Nits（批量）

条目 3 补 Proposed Changes 主体（删除范围 `rm -rf ~/.deepseek/agents/`、依据冲突 C、验收指针）；"verify.sh 形态已按裁决取消"改为"live 断言统一走 expected.json，不另立 verify 脚本"；条目 14 adopt 补 dirty 分支（diff 呈现 → 作者裁决 drop 或 fork in-house）；Stage 3 验收改可测（grep `{{` 占位符与替换说明一一对应 + 无 Go/GPFS 字面残留）；条目标题补类型标记（2 Delete、3 Delete、6 Modify、12 Modify）；adopt 枚举补"删除退役"；dsh 路径措辞改"NOTES.md 验证结论给出的实际路径"；内嵌验收改指针统一；"零误报"定义 = 零 error 零 warn；doctor v0 注明硬编码期望清单与 Stage 2 切换点；`--force` 落点（条目 7）；凭据 warn 赋检查 ID（并入 C7 live）；物化次序 in-house 优先（条目 7c）；commands 双根验证动作归属（条目 5 NOTES 或 Stage 2 会话验证清单）；attribute.sh 退役点 = Stage 1 验收通过后删除；验收分命令级/人工级两栏；Q2' 双候选皆败 fallback = 输出 unverified 不计验收；Stage 2 临时 HOME 验收前 stop 真机 8228 服务；F7 措辞——repo lock 实为更新的一份（非"旧拷贝"），归因输入 = 双份并集，software-factory 归因证据 = mattpocock 上游 clone 现存；FROZEN.md 生成者 = attribute.sh 第二步。

## 核对通过项（摘）

数量口径全自洽（104 闭合）；Modify/Create 对象全部现存/不存在符合语义；v3 lock 无 commit 锚属实；条目 4 前提准确（正文仅 archify/diagram-design，无 teach；code-walk 部署缺口属实）；条目 16/17 前提准确（配套文件确不在 repo）；C1-C7 均有实施落点；sync-mcps.sh 除 configure 路径外确无遗漏子命令；术语与 FeatureRange 无新旧混用；无"视情况"类模糊词。
