# Stage 8 — Intermediate Zoom Out Report（Rev.2 差异审计）

* **Target:** `docs/designs/multi-harness-agent-repo-governance.md`（Rev.2，389 行，全文）
* **Reviewer:** egm-zoom-out（fresh-context，标准 zoom-out-standard）
* **审计上下文:** zoom_out_report.md / comprehension_report.md / critic_report.md / goldfish_review_report.md（D1-D12 裁决）
* **Date:** 2026-11-06

## 一、新问题 findings

### N1 [🔴] delta guard 无基准态定义——无法区分"node 本地漂移"与"repo 正常前进"，CUJ 3 与 guard 行为互斥

* **定位:** L158（delta guard 段）、L78-82（CUJ 3）、L33（G1c）、L264（NFR）
* **发现:** guard 比对双方是 node 目录 vs repo 当前内容。但 CUJ 3 日常流（repo 编辑 → commit → restore）中 node 持旧版、repo 持新版，diff 必然非空——首次 restore 必中止。"确认丢弃后重跑"条件不变仍中止，实际出路只剩 `--force`。
* **理由:** B3/F7 修复只落了"中止"一半，丢了原始提议的基准方案（lock `deployedHash`）。没有"上次物化态"基准，dry-run diff 无法区分"node 有要保护的独立改动"（archify 事故模式）与"repo 合法前进"。后果：每次正常部署双跑 + `--force` 习惯化 → guard 沦为装饰，数据丢失威胁后门回归；或实现者自行发明基准。
* **建议:** 钉死基准语义：物化成功后记录部署基线（lock v4 条目加 `deployedHash` 或独立 `hack/.deploy-state`）；guard = node vs 基线（非 node vs repo 当前）。基线一致 → 允许覆盖；不一致 → 才是漂移，中止 + adopt/discard。

### N2 [🟡] 冻结语义与 pull 镜像粒度冲突：上游已删条目在活动源 vendor 路径下，"pull 永不触碰"无机制支撑

* **定位:** L327（归因矩阵）、L136/L154（pull 机制）、L202（C5）、L31（G1a）
* **发现:** 7 个 lock-only 冻结中 6 个属未声明源（pull 天然不触碰）；但 resolving-merge-conflicts 归入 `vendor/github.com/mattpocock/skills/`——已声明、每次 pull 都 rsync 的活动源目录。rsync `--delete` 粒度（整源 vs 按 skill 逐目录）未钉死：整源粒度会删掉冻结条目。C5"一一对应"若读作双向，该条目恒违规。
* **建议:** 二选一写明：(a) pull 钉死 per-skill 粒度 rsync（只镜像上游现存 skill，天然保留冻结遗留），C5 明确单向（lock→目录）；(b) 上游已删条目移入 frozen 区与活动源物理隔离。

### N3 [🟡] NFR"bash 3.2 兼容"与 doctor"关联数组"直接矛盾

* **定位:** L39/L194 vs L265
* **发现:** `declare -A` 需 bash ≥4.0；macOS 自带 bash 3.2。doctor v0 在 Stage 1 交付，照字面实现即撞墙。
* **建议:** 去"关联数组"措辞，改"平行索引数组或 `check_c1_sev` 类命名约定函数即注册表"。

### N4 [🟡] attribute.sh 永久职责可疑，冻结记录无机器可读载体

* **定位:** L129、L31、L190
* **发现:** 归因本质一次性迁移；常驻职责"防无归因再出现"面临无数据源困境（冻结仓不进 lock 无 manifest，doctor 只能 git 考古）；"记冻结日期"无落点。
* **建议:** 冻结记录唯一载体 = lock v4 sources 段加 `frozen: true`（代价最小）；"防再出现"并入 C5 子检查；attribute.sh 标注 Stage 1 一次性工具、迁移完成退役。

### N5 [🟢] 计数与措辞残留簇

Problem 5 计数歧义（未声明源 5 个、其条目 6 个，+R-M-C 共 7）；C1 对 unknown 沿用"镜像内容不可改"（M5 漏改，应"冻结内容"）；供应链缓解"HEAD ≠ 锚时显式确认"条件恒真（pull 即取 HEAD 写锚，应删，实际缓解就是人工 git diff）；白名单段 C3（删 symlink）谈 delta guard 无意义；"共享根约定"是 expected.json 之外的第二个期望源（应并入某份 expected.json）。

### N6 [🟢] 冻结条目目录名规则

vercel-react-best-practices 类历史条目（v3 lock skillPath 叶名 ≠ 现装名）——钉死：冻结条目目录名 = 现有 install-name（保持现状等价），"叶名即部署名"规则只约束今后 pull 的条目。

### N7 [🟢] C4/C7 与 sync-agents list / sync-mcps status 职责吸收关系未声明（F13 残留）

一句"C7 live 消费 sync-mcps status 输出；sync-agents list 降级为 doctor 的格式化视图"即可闭合。

### N8 [🟢] pull 对权威节点自身的物化时机未写

数据流图物化只画在 setup/restore 分支，CUJ 2 却断言 pull 触发 guard——钉死：pull 写 repo 后自动对本节点 restore（guard 在此触发）。

### N9 [🟢] Stage 6 残留小项簇

rank 500/200 量纲定义；sideshow 一句介绍；Alternative G 的 #361 补仓库上下文；"物化 = 复制而非链接"显式定义；Stage 2 #14 adopt 的上游参照来源（自行 depth-1 clone）写明。各补一句。

## 二、前序发现修复验证（摘要）

* **Stage 5:** F1/F2/F3/F4/F5/F8/F9/F10/F11/F12/F14 成立；F6 未采纳（作者裁决保留接源，体积论据已证伪，可接受）；F7 **未闭合**（→N1）；F13 未闭合（→N7）；F15 文字缝补（commands 双根是否泛化 C3 待一行裁决）；F16 有意延后。
* **Stage 7:** B1/B2/M1-M15/N 簇全部成立；B3 **文字缝补**（→N1）。
* **Stage 6:** Major #1-#7 全部成立；Nit 中 #9/#16/#17/#18/#24/#11 未闭合（→N9）。

## 三、高空终检

Stage 5 提议砍六项，Rev.2 实砍五项（backup-own、checks/、slot-map+C8、verify.sh、orphan 簿记、L4），adopt 收敛为单一显式回写通道；新增物（delta guard、Risks、expected.json、单一 pull 节点）各自小且有依据。剩余结构与"单人、104 skills、4 harness"基本成正比。还能删：attribute.sh 常驻化（N4）；`harness/*/config/` 备份若凭据排除规则长期空转可整体降级 Future（第一个被现实砍掉的三件套成员候选）。

## 总体判断

Rev.2 已接近可实施：前序 16+19 项发现除 F7/B3 外全部真实闭合，"砍一半新增结构"目标基本达成。最薄弱一环是 delta guard 基准态语义缺失（N1）——不补上，CUJ 3 日常流要么 `--force` 习惯化（guard 名存实亡），要么实现者自行偏离设计。次弱是 N2（冻结与 pull 粒度）与 N3（bash 3.2 矛盾），均为句子级补丁，不动骨架。
