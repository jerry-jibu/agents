# Stage 7 — Critic Review Report（Round 1，修订后文档）

* **Target:** `docs/designs/multi-harness-agent-repo-governance.md` FeatureRange 1..263（术语跨段核对至 DetailedRange 264..380）
* **Reviewers:** egm-design、egm-structural、egm-style（并行 fresh-context，标准 feature-spec-standard）
* **Date:** 2026-11-06
* **裁决前事实核查（本会话实测）：** launch-video ∈ modem-dev/sideshow（上游 skills/ = launch-video + sideshow）→ 归因矩阵修正：unknown 17→**16**、sideshow 1→**2**；addyosmani references 0.1MB/份（×25 ≈ 2.5MB 上限）；`~/.zcode/skills` 实测 79 条 symlinks（repo 104 vs node 79 差集 = C4 首个实捕对象）。

## 汇总：🔴 Blocker ×3（全收敛）、🟡 Major ×15、🟢 Nit ×1 簇

### B1 [🔴×3 收敛] 旧税则/旧数字残留清扫（design#1、struct F1/F2/F3、style F1/F2）

修订遗漏点：CUJ 2（L67 `skills/vendor/<source>/**`、`skills/own/` 零变化）、C2（L184 `own/ 或 vendor/`）、C4（L186 `vendor+own`）、CUJ 3 标题（L69 "own 数据流"）、**Stage 1 条目 7（L318 `skills/vendor/<source>/`、`永不触碰 own/`、`backup 只收 own/`）与条目 8（L323 `own/ 不入 lock`）**——同一 Stage 内与条目 6 新矩阵自相矛盾；Alternative A（L207）"79 skills"旧口径；Problem 第 5 条（L22）"3 个孤儿源"（实为 5 源 7 条目）。

### B2 [🔴] agents 链归属与 deepseek 部署矛盾（design#2，连带 comprehension#4）

"不变部分"（L200）声明 agents "四 harness deploy 保持现状"，与部署矩阵"deepseek 无个人目录、`~/.deepseek/agents/` 死配置删除"互斥——照办会复活刚删的死配置。且 `sync-agents.sh`（目录树）与 `sync-skills.sh agents`（验收引用）两种说法未调和，"生成"一步未定义。修复：deploy 链收敛为 zcode/claude/antigravity 三 harness（deepseek 目标移除）；写明链路 = `sync-skills.sh agents`（从 skill personas 的 agents/*.md 生成 `~/.zcode/agents/`）→ `sync-agents.sh collect`（收进 repo `agents/`）→ `sync-agents.sh deploy`（三 harness）；CUJ 1 L61 "各 harness"具名化。

### B3 [🔴] node 侧破坏性覆盖无守卫——威胁模型半闭合（design#3）

全部 guard 只检查 repo 工作树；node 侧对 vendor skill 的编辑（archify 事故的行为模式）与 node 上新写的 in-house skill，会在 pull/restore `rsync --delete` 时**无声消失**，C4 只做目录名差集不做内容比对，三个环节零告警。修复：物化前置 delta guard（lock v4 增 `deployedHash` 或 dry-run diff），漂移非空即中止并列 diff；guard 覆盖 pull/restore/doctor `--fix` 三处；NFR 补 node 侧可恢复性。

### M1 [🟡] lock v4 schema 统一（design#4、struct F5/F6、style F6、comp#2）

`sources[]` 短名 vs `source` 字段 owner-repo 两套命名；install-name 三形态（对象键/字段/驼峰）；sourceUrl 丢失（lock-only 冻结源不在 sources.conf，provenance 退化为无 URL 的名字）；`owner-repo` 扁平化歧义无规则。修复：per-source 注册段（url + repo 标识）或条目保留 sourceUrl；全 schema 统一 owner-repo；install-name 唯一形态 = 对象键，别名机制 = sources.conf 可选第 4 字段；扁平化规则钉死（`owner-repo`，`/`→`-`，无嵌套）。

### M2 [🟡] orphaned 语义与枚举（design#5、struct F9/F12）

Problem L22 "3 个孤儿源"过期（5 源 7 条目）；条目 8 只枚举 vercel×2+fireworks，漏 anthropics（skill-creator）、GoogleChrome（modern-web-guidance）、mattpocock（resolving-merge-conflicts）；`orphaned` 语义应为 "lock-only 冻结"（含上游仍存但未声明的源），不是 "上游已无"。

### M3 [🟡] 单一 pull 节点约束缺失（design#6）

多节点各自 pull 后 push，vendor/** 与 lock（单文件 JSON）必然合并冲突，而 NG1 拒绝处理冲突合并——架构制造了自己宣称不做的场景。修复：G1/NG1 加一句"pull 仅在单一权威节点执行，其余节点只 consume"。

### M4 [🟡] pull 崩溃一致性/幂等未定义（design#7）

6 次 clone + 多目录 rsync + lock 重写的事务性：单源失败全中止（保持现 die 行为）、lock 写入 temp+rename 原子、中断重跑幂等收敛——三条声明入正文；C5 的 warn 定级复核。

### M5 [🟡] vendor/unknown 无生命周期（design#8、style F25）

冻结即永久、仍部署、不可复核不可晋升不可退役、"勿手改镜像语义"措辞错位（unknown 不是任何东西的镜像）。修复：记录冻结日期；复用 adopt 通道给出晋升 in-house / 归编某源 / 删除的复核路径；措辞改"冻结语义：勿手改、pull 永不触碰、经 adopt 晋升或退役"。

### M6 [🟡] 缺独立 Risks & Mitigations 章节（struct F13、design#9）

标准明文要求；安全面零提及（上游 SKILL.md 即代理指令直通 4 harness；MCP 配置备份入 repo 是否含凭据未声明）。修复：新增章节承接：供应链（上游 HEAD ≠ lock 锚时要求显式确认 + 人工 diff 为缓解 + 风险自留声明）、多节点并发（M3）、harness 行为漂移（M8）、lock/树漂移（M4）。

### M7 [🟡] CUJ 1 不可执行（design#10）

Given 缺 Node 运行时/依赖前提（sideshow 服务）；L3 对 antigravity（Q2'）/deepseek（路径待验证）无确定写入目标；L1 物化范围（共享根 vs per-harness 副本）未定义。修复：Given 补前提；L3 加前置条件（未验证 harness 完成前 L3 限定已验证者，其余标 unverified 不计验收）。

### M8 [🟡] NOTES 验证日期无过期语义（design#11）

harness 行为随版本变化，Q1 类结论固化进期望态后 doctor 会静默地错。修复：doctor 对超期验证（如 >90 天）输出 warn。

### M9 [🟡] C1 对 vendor 镜像判 error 制造不可清零红灯（design#12）

`name == 目录名` 对 in-house 成立、对 vendor 精确镜像不可修（修复被勿手改规则禁止），CUJ 1 "全绿"结构性不可达。修复：分区定级——in-house error / vendor+unknown warn。

### M10 [🟡] 归因矩阵勘误（struct F11、design#5 附注）

launch-video → sideshow（本会话核实）；unknown 17→16、sideshow 1→2；"39 matt"行注明构成（software-factory ∈ matt 上游现存；resolving-merge-conflicts ∈ lock-only 因上游已删）；node 79 vs repo 104 差异说明（C4 首个实捕对象）。

### M11 [🟡] repair 白名单四处不一致 + C6 自相矛盾（style F5、comp#3）

G7/NFR/检查表/白名单清单四套口径；C6 自动修复列"是（列出后人工确认删除）"自相矛盾。修复：定稿一份白名单 = symlink 去重/重建、重部署缺口（带 B3 delta guard）、lock 元数据补录；**删除"frontmatter 小修"**（C1 本就不可自动修）；C6 改"否（列举后人工确认删除）"。

### M12 [🟡] 冗余收敛（style F8-F13）

干净树规则六处近逐字重复；Problem"解法方向"段与 G1-G8 重复；"in-house 不进 lock"五处、"第一公民"四处、setup-matt 前置三处。修复：各收敛至一处定义 + 其余引用。

### M13 [🟡] 规范行畸形 glob（struct F14、style F24）

restore 规则 `` vendor/**/*.SKILL 目录 `` 非法记法。修复：改 `vendor/<owner>-<repo>/<name>/` 与 `in-house/skills/<name>/`。

### M14 [🟡] 槽位词汇与同名策略统一（struct F10、comp#14、design#16）

CUJ 5 八槽中文名 vs slot-map 九槽英文名（缺 diagnose）；CUJ 4 缺 Given；G4 依赖遮蔽 vs 部署硬失败的域未定义。修复：CUJ 5 对齐九槽规范名；CUJ 4 补 Given；写明 install-name 全局唯一、in-house 同名胜出并提示、vendor↔vendor 同名才硬失败。

### M15 [🟡→闭合] references 体积基线（design#17）

实测 0.1MB/份 ×25 ≈ 2.5MB 上限——写入一句即闭合（zoom-out F6/F8 的"复制放大"论据据此降级）。

### N 簇 [🟢] 术语与文风批量（style F14-F30、struct F15-F18、design#13-15）

Deferred 标签（Reason for Deferral）、G1 修订注记删除（元评论交 git history）、"税则"隐喻替换、G1 长句拆子条、槽位内联改两列小表、Q1/Q3 分支子列表、dsh 首现定义、node/节点统一、"正文 prose"、"第三站"展开、"守卫不变"指代、12 vs 10 agents 对账（实测 `~/.gemini/config/agents/` 构成后注明）、CALIBRATE 形容词（近乎零/极小/大版本演进/根治/在路上）、"6 个源"补（现有 4 + 新增 2）、HR 对称、已闭合小节改名。

## 通过项（三评审一致，摘）

Problem 机制级证据与实测吻合；Alternatives 七项结构合规（作者自裁、无维护者无链接归因）；25 同名/16 无归因经 lock 逐条核对成立；双区+git 权威 repo 侧闭环；误报控制与 repair 分级设计正确；Q2' 收敛质量；Non-Goals 2/3/4 边界真实；bash 3.2/rsync 尾斜杠 NFR 落地；G2 用旧路径正确（Stage 0 先于重构）；CUJ 与 Goals 对应成立。

## 处置去向

全部进入 egm-resolve：B1-M15 逐条 PROPOSE FIX（无 CONTEST 候选——三条 🔴 均为修订遗漏或机制补强，无可辩护的保留理由）；N 簇批量修。详见 goldfish_review_report.md。
