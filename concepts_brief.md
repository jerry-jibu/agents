# 概念简报：多 harness 智能体环境仓库的治理与进化（jerry-jibu/agents）

- **Author:** jerry-jibu（`git config user.name` 未设置，按指示回退）
- **Date:** 2026-11-06
- **Mode:** BRAINSTORM（EGM 七视角攻击式头脑风暴）
- **Target repo:** `/Users/jibu/code/github.com/jerry-jibu/agents`
- **下一步入口:** 本文件是 `egm-brainstorm` 的产物，按用户决策 4，下一站是 `egm-draft` 起草实施方案。

## 视角覆盖（Reviewer Status）

| Lens | 状态 | 说明 |
| --- | --- | --- |
| `egm-design` | completed | 架构与接口设计视角 |
| `egm-codebase-details` | completed | 仓库实测细节视角 |
| `egm-zoom-out` | completed | 战略与定位视角 |
| `egm-comprehension` | completed | 概念清晰度视角 |
| `egm-implementation-readiness` | completed | 落地可行性视角 |
| `egm-structural` | completed | 结构与布局视角 |
| `egm-inventive-catalyst` | completed | 创新与矛盾催化视角 |

> 执行方式说明：本环境未提供子代理派生工具，七个视角由 Synthesizer 依据仓库实测文件内联执行（等效的单体模拟），实测基线包括 `README.md`、`hack/sources.conf`、`hack/sync-skills.sh`、`.skill-lock.json`（version 3）、`docs/agents/{feature,bugfix}-workflow.md`、`agents/`（10 个 egm-*.md）、`skills/`（约 79 个目录）。概念描述中的 8 条 ground truth 未被推翻，全部成立。

## Overview

本概念要解决的问题：`jerry-jibu/agents` 是个人智能体环境仓库，同时承担"上游 skills 的备份镜像"与"自研资产的 source of truth"两种数据流方向相反的角色，导致三类已验证冲突（archify 本地编辑将被 `rsync --delete` 抹掉、ZCode skill 双读重复、`~/.deepseek/agents/` 死配置），并且 workflow 文档写死了另一个项目的内容。

概念的六项固定决策：（1）`skills/vendor/<source>/<name>/`（pull-only 上游镜像）与 `skills/own/<name>/`（自研，repo 即 source of truth）双区治理，archify 本地编辑回滚；（2）repo 内建 per-harness 目录（部署产物、配置备份、harness 专属资产），每个 harness 配 verify / healthcheck / repair；（3）SKILL.md frontmatter 增加 `depends-on:` 显式声明依赖；（4）workflow 文档通用化，在 grill 与 to-spec 之间插入 egm 方案设计阶段，code-review 后接 egm 偏差评审；（5）新增 addyosmani/agent-skills 与 cathrynlavery/diagram-design 两个源（后者需支持根级 SKILL.md）；（6）新建 `hack/doctor.sh` 方向的 skills 健康检查与修复。

目标 harness：ZCode（`~/.zcode/`）、Claude Code（`~/.claude/`）、Antigravity（`~/.gemini/`）、deepseek-harness（原生读 `~/.agents/skills`，rank 500，零部署即达）。

## Analysis

### 各视角一致认可的方向（共识）

1. **双区拆分方向正确，且是对根因的正确命名。** 七个视角无人反对 `vendor/own` 拆分。真正的病根是"上游镜像与自研资产同处一个扁平 `skills/`，数据流方向相反"（`sync-skills.sh` 的 pull 把上游 rsync 到 node、再从 node rsync 回 repo 扁平目录，repo 只是 node 状态的第三站镜像，不是权威）。
2. **`depends-on:` 是对真实 bug 的修复，不是锦上添花。** code-walk 依赖 `archify`、`diagram-design`、`teach`，但依赖只写在正文 prose 里（SKILL.md 第 33 行附近），且 code-walk 本身存在部署缺口（repo 有、`~/.agents/skills` 没有）。frontmatter 显式化 + doctor 检查存在性与部署性，两件事互相成就。
3. **doctor 应该是"期望态对比"，不是绝对规则。** dsh 的 `~/.agents/skills` 零部署是期望态（原生直读），如果 doctor 用"repo 有什么 node 就该有什么"的绝对规则会大量误报。期望态清单（per-harness 应有什么）是误报控制的关键。
4. **workflow 通用化必要性有实测证据。** 两份 workflow 文档写死了 agent-data-workspace 项目（Go 服务、GPFS/EE 存储底座、journalctl、etcd、磁带驱动器），且引用的配套文档 `issue-tracker.md`、`triage-labels.md` 以及 `docs/proposals/`、`docs/adr/`、`CONTEXT.md` 等路径在本 repo 不存在——这层按后续裁决处理：配套属目标项目初始化产物，repo 不 track，模板声明前置条件即可。通用化同时处理这两层问题。

### Goldfish 关键异议（按重要性排序，每条注明来源 lens）

1. **【根因异议】只拆目录不改数据流声明，双区会退化为新的脏状态。** 实测 `sync-skills.sh`：pull 顺序是"上游 → `~/.agents/skills` → repo 扁平镜像"，backup 是"node → repo（additive）"，restore 是"repo → node（`--delete`）"。如果只是把 `skills/` 改名成 `skills/vendor/<source>/` 而不重写这三条流的方向规则（pull 只写 vendor、backup 只收 own 与配置备份、restore 分区），node 上的脏状态依旧会经由 backup 污染 repo。**建议**：在 README 与脚本头部显式写明单向数据流声明："repo 是 source of truth，node 是部署目标"；pull 永不触碰 `own/`；backup 不再全量收 node。（来源：`egm-zoom-out`、`egm-structural`、`egm-codebase-details`）
    【2026-11-06 用户裁决】数据流以 git 为权威媒介：repo 是唯一权威；节点上的更新走 `git commit` + `git push`，其他节点 `git pull` 后更新本地——脏状态由 git 历史兜底，不会污染 repo。rsync 流（pull/backup/restore）只负责物化工作树；脚本侧加强一条：破坏性覆盖前检查 repo 工作树干净（脏则先 commit 或中止），把"git 兜底"变成机制而非习惯。
2. **【数据丢失风险】archify 回滚前必须先归档本地编辑。** archify 的本地编辑同时存在于 node 与 repo（backup 是 additive 的），"回滚为 vendor 原样"如果直接执行 pull，`rsync --delete` 会把两处一起抹掉。用户决策已定"回滚"，本异议只针对执行安全：**建议**先 `git branch archive/archify-local-edits` + 导出 diff 存档（或把有价值的编辑提炼成 `skills/own/` 下的新 skill），确认归档可恢复后再回滚。（来源：`egm-implementation-readiness`、`egm-codebase-details`）
    【2026-11-06 用户裁决】不归档，直接 drop 本地变化，采用上游 remote 版本。执行面需两处同步清：repo 工作树 `git restore skills/archify/`，node 副本重新物化（pull/restore），防止 backup 流把残留带回。
3. **【命名冲突策略缺失】vendor 按 source 分层后，deploy 端扁平布局的重名问题没有答案。** egm 源与 addyosmani 源可能撞名（两者都是通用技能命名风格）。**建议**：deploy 端 `~/.agents/skills/` 保持扁平（dsh rank 500 原生直读，分层会破坏其他 harness 的发现）；lock 增加 `install-name` 字段；同名安装默认硬失败并提示手动指定别名，绝不静默覆盖。（来源：`egm-design`、`egm-structural`）
4. **【`|.|` 根级 skill 的解析缺陷】现有脚本对根级 SKILL.md 会产出错误目录名。** 实测 `sync-skills.sh` 第 47 行 `${subdir:-.}` 已默认支持子目录为空时取 repo 根，但 `find "$src/." -name SKILL.md` 得到的技能名是 `basename "$(dirname "$src/./SKILL.md")"` 即 `.`，会 rsync 到 `~/.agents/skills/.`（灾难）。且 maxdepth 4 的 find 会误扫 `.claude-plugin/`、`.codex-plugin/` 等适配目录里的 SKILL.md。**建议**：sources.conf 增加第 4 字段（根级 skill 的显式名，缺省取 repo 名）——lock 里 `fireworks-tech-graph` 的 `skillPath: "SKILL.md"` 已有"按 repo 名命名"的先例；find 需 exclude 插件适配目录。（来源：`egm-codebase-details`、`egm-implementation-readiness`）
    【2026-11-06 勘误与裁决】复核实测：diagram-design 的 SKILL.md 位于 `skills/diagram-design/`（自含 `assets/ references/ scripts/`，引用均为 skill 内相对路径），是标准 `url|skills|` 形态——此前"根级 SKILL.md"为误报（源探测命令的静默回退所致，勘误）。本源无需第 4 字段；find exclude 适配目录与第 4 字段降级为通用防御加固（该 repo 实测仅 1 个 SKILL.md，无适配目录误扫风险）。部署目标确认：`~/.agents/skills/<install-name>/` 保持扁平；定向修复以 hack/ 脚本落实（pull 加固 + doctor 增加"部署目录无 `.`/杂散目录"检查）。
5. **【addyosmani references 断链在"纯镜像"框架内无解，需要部署期策略】** sources.conf 的 `shared_dirs` 机制（把仓库根的 `references/` 复制进每个 skill，egm 的 `agents/,resources,docs` 先例）能表达该源，但代价是复制放大，且与上游 issue #361 同构的问题只是被掩盖。**建议**：v1 接受复制方案 + doctor 增加"共享树与上游漂移"检查；部署期路径改写列为 future work，不阻塞本期。（来源：`egm-design`、`egm-codebase-details`）
6. **【ZCode 双读的修复顺序反了：先验证机制，再写 repair】** "去重 symlink"是治标。需要先回答一个事实问题：ZCode 是否可配置 skills 搜索根？若可，直接把搜索根指向 `~/.agents/skills` 并删除 `~/.zcode/skills` 整个目录（symlink 层取消）；若不可，则要确认 ZCode 是否真的同时扫 `~/.zcode/skills` 与 `~/.agents/skills` 两处（若双扫，symlink 方案本身就是重复源，repair 无法消除）。**建议**：此项验证实验作为 `harness/zcode/` 目录的第一项内容（一页 NOTES.md 记录结论），doctor 的"无重复注册"检查以该结论为期望态依据。（来源：`egm-inventive-catalyst`、`egm-codebase-details`）
7. **【per-harness 目录的最大风险是把未验证猜测固化成结构】** `~/.deepseek/agents/` 死配置就是"先建目录后验证"的产物；`~/.gemini/config/mcp.json` 路径仍是未验证猜测（可用 ANTIGRAVITY_MCP_CONFIG 覆盖）。**建议**：每个 `harness/<name>/` 目录以两样东西为第一公民——已验证机制说明（README：该 harness 实际读哪里、怎么读、验证日期）+ verify 脚本（fail loudly，不静默跳过）；未验证路径标注 experimental；dsh 的 skills 零部署写入期望态清单而非当成异常。（来源：`egm-comprehension`、`egm-codebase-details`、`egm-design`）
8. **【lock 文件的历史包袱要在 schema 升级时一并清理】** 实测 `.skill-lock.json`（version 3）里存在 sources.conf 已移除的源（`vercel-labs/agent-skills`、`vercel-labs/skills`、`yizhiyanhua-ai/fireworks-tech-graph`）——孤儿条目；且条目只有 folder hash 与时间戳，无 commit 锚，"锁版本仅靠 git"实际上锁不住上游版本。**建议**：lock v4 增加 `zone`（vendor/own）、`source`、`commit`（depth-1 clone 的 HEAD）、`install-name`；孤儿条目保留 provenance 但标注 `orphaned: true`；`own/` 区不进 lock（git 即版本）。（来源：`egm-codebase-details`、`egm-structural`）
9. **【大爆炸迁移风险】79 个 skill + lock + sync 三条流 + agents 生成 + 4 harness 部署一次切换，失败时不可回退。** **建议**分批：第一批只迁 egm 源到 `vendor/egm/`（它 shared_dirs 最复杂、且 `sync-skills.sh agents` 子命令依赖它生成 personas，能最早暴露全链路问题）；第二批迁其余三个源；`own/` 先迁三个自研（code-walk、code-to-spec、architecture-diagram）。每批验收标准：单源 pull 幂等重跑无 diff、restore 全量后 doctor static 全绿。（来源：`egm-implementation-readiness`、`egm-structural`）
10. **【workflow 模板对 mattpocock skill 名的硬依赖是外部风险】** 上游改名即断链，而我们不控制上游。**建议**：模板引用"能力槽位"（如 grill 槽位、spec 槽位、tdd 槽位）而非裸 skill 名，另附一张 slot → 当前 skill 名的映射表；doctor 检查映射表指向的 skill 存在且已部署。同时修复文档内部断链（`issue-tracker.md`、`triage-labels.md` 等配套要么补齐、要么改为占位符）。（来源：`egm-zoom-out`、`egm-comprehension`）
    【2026-11-06 用户裁决】`issue-tracker.md`、`triage-labels.md`、`CONTEXT.md` 等配套是 `/setup-matt-pocock-skills` 在目标项目初始化时生成的中间产物——repo 不 track、不保存这些结果。模板不做补齐/占位修复，改为显式声明前置条件："目标项目需先经 `/setup-matt-pocock-skills` 初始化产生配套文档"；"断链"重定性为环境前提而非缺陷。能力槽位 + 映射表建议保留。
11. **【bootstrap "setup 完成"没有定义】** "clone 后一条命令"到什么程度算完成是开放问题，直接影响验收。**建议**分层定义：L0 结构就绪（目录 + lock 校验）→ L1 skills 部署 + 无重复注册 → L2 agents 部署 → L3 MCP 配置 + 服务存活 → L4 workflow 文档投放；`hack/setup.sh [--level N]` 默认到 L3，doctor 作为每层验收门。（来源：`egm-implementation-readiness`、`egm-design`）
12. **【`depends-on:` 语义未定义会导致 doctor 误报】** 名字解析顺序（own 优先于 vendor？跨区重名取谁？）、依赖缺失时的严重级别、是否覆盖非 skill 依赖（MCP 服务、外部命令如 gh/git）。**建议**：v1 只建模 skill 名依赖，解析顺序 own → vendor（同名时 own 优先并在 doctor 提示）；MCP/命令依赖本期不进 frontmatter，由 doctor 的 MCP 检查独立覆盖。（来源：`egm-comprehension`、`egm-implementation-readiness`）

### 开放设计问题的收敛建议（对应上表异议的推荐答案）

| 开放问题 | 推荐答案 | 依据异议 |
| --- | --- | --- |
| deploy 端是否保持扁平 | 保持扁平；重名靠 `install-name` + 硬失败 | #3 |
| harness 目录 vs 全局 manifest 边界 | harness 目录 = 部署产物 + 配置备份 + 专属资产 + verify；全局 = lock（vendor 出处）+ 期望态清单 + doctor 规则。同一信息只存一处，harness 目录不复制全局信息 | #7、#11 |
| doctor 静态 vs live 分层 | static（frontmatter、depends-on、重复注册、repo vs node 差集）默认跑；live（MCP 服务存活、harness 实际读取验证）用 `--live` 显式开启；期望态清单控误报 | #6、#7 |
| repair 安全边界 | 白名单自动修：去重/重建 symlink、补部署缺口、frontmatter 小修；必须人工确认：删死配置（`~/.deepseek/agents/`）、回滚 vendor、任何覆盖 node 本地改动的操作 | #2、#6 |
| rsync --delete 与 vendor 的交互 | pull 只对 `vendor/<source>/<name>` 生效，永不触碰 `own/`；单源单 skill 粒度 = 按 lock 的 install-name 定位目录；破坏性覆盖前 repo 工作树须干净（git 兜底机制化）。根级源第 4 字段降级为通用加固（diagram-design 实测为标准 `skills/` 形态，勘误见异议 #4） | #1、#4 |

## Goals vs. Non-Goals

### Goals（固定决策重申 + 评审补充）

1. 双区治理：`skills/vendor/<source>/<name>/`（pull-only）与 `skills/own/<name>/`（source of truth）；数据流以 git 为权威（节点更新 commit/push、其他节点 pull，rsync 只物化工作树，破坏性覆盖前工作树须干净——异议 #1 裁决）；archify 本地编辑直接 drop 回滚为 vendor 原样（用户裁决，repo `git restore` + node 重物化两处同步清）。
2. per-harness 目录（推荐 `harness/zcode|claude|antigravity|deepseek/`），内容三类：部署产物、配置备份（mcp.json 等）、harness 专属资产（commands/hooks 等），每个 harness 配 verify / healthcheck / repair；目录以"已验证机制说明"为第一公民（异议 #7）。
3. `depends-on:` frontmatter 显式化；语义按异议 #12 的 v1 定义收窄。
4. workflow 通用化：Go/GPFS 示例模糊为占位符；grill 与 to-spec 之间插入 `egm-brainstorm → concepts_brief → egm-draft` 方案设计阶段；code-review 之后接 `egm-review` / `egm-drift-report` 偏差评审；外部 skill 依赖用能力槽位 + 映射表表达（异议 #10）；配套文档（issue-tracker.md 等）声明为 `/setup-matt-pocock-skills` 初始化的前置条件，repo 不 track 中间产物（异议 #10 裁决）。
5. 新源接入：addyosmani/agent-skills（shared_dirs 复制策略）、cathrynlavery/diagram-design（根级 SKILL.md，sources.conf 第 4 字段 + exclude 适配目录，异议 #4）。
6. `hack/doctor.sh`：依赖成立、引用文件存在、frontmatter 合法、无重复注册、部署完整性（repo vs `~/.agents/skills` 差集）、MCP 配置与服务存活；repair 按白名单/人工确认两级（上表）。
7. 评审补充目标：修复 ZCode 双读（先机制验证后 repair，异议 #6）；清除 `~/.deepseek/agents/` 死配置；补 code-walk 部署缺口；bootstrap 分层定义（异议 #11）；README 的 Node layout 章节随新结构同步更新。

### Non-Goals（初稿三条，评审后均维持，附理由）

1. **不做多机同步/冲突合并**——维持。repo 是可移植备份单元，"导入新环境"由 Goals 的 bootstrap 分层覆盖，不需要双向同步协议。
2. **不做 skill 自动升级迁移工具**——维持。pull 即升级；但按异议 #8 补强：lock v4 加 commit 锚，使"回到上游哪个版本"可回答，弥补"锁版本仅靠 git"的缺口。
3. **不覆盖 harness 无法自定义的部分**（如 zcode 内置 agents）——维持。与异议 #7 一致：只治理有已验证配置面的部分。
4. （新增，源自 Alternatives）**不引入 git submodule 承载 vendor**、**不做 repo 直连 live store 的 symlink 方案**——理由见 Alternatives Weighed。

## Alternatives Weighed

| 备选方案 | 结论 | 理由 |
| --- | --- | --- |
| vendor 用 git submodule（天然锁版本） | 否决 | 个人 repo 场景过重：submodule 的 init/update 心智负担、与现有 pull/backup/restore 链路不兼容；改为 lock v4 增加 commit 锚，以更低成本获得版本可追溯（`egm-structural` 提出，`egm-implementation-readiness` 附议） |
| repo 直接当 live store（`~/.agents/skills` symlink 到 repo `skills/`） | 否决 | 单 repo 单目录方案优雅，但 node 侧的实验性改动会直接弄脏 repo，vendor 区失去防误改屏障，且与 dsh rank 500 的原生读取路径耦合过深（`egm-inventive-catalyst` 提出，`egm-implementation-readiness` 否决）；保留其洞见：把 repo 定位为唯一 source of truth、node 定位为纯部署目标 |
| 维持扁平 + `.gitignore` 排除 vendor | 否决 | 失去 vendor 备份价值，lock 与 sources.conf 失去对应物，冲突 A 无解（`egm-design`） |
| doctor 写成单体脚本 | 否决 | 检查项会持续膨胀；改为检查注册表（`hack/checks/*.sh`，每项带 severity 与 auto-repairable 标志），repair 按 RP-1/RP-2 分级 |
| workflow 硬编码 mattpocock skill 名 | 否决 | 上游改名断链；改为能力槽位 + 映射表（`egm-zoom-out`、`egm-comprehension`） |
| harness 目录用点前缀命名（`.zcode/`） | 否决 | 点前缀在惯例上暗示机器生成/工具私有目录；`harness/<name>/` 表达人工治理的资产目录（`egm-structural`） |

## Key Decisions & Staging for Next Steps

### 关键决策（待 egm-draft 固化为方案）

- KD-1 git 为权威的同步模型（用户裁决）：repo = 唯一权威，节点更新走 git commit/push，其他节点 git pull 后更新本地；pull 只写 `vendor/`，backup 只收 `own/` 与配置，restore 分区执行；rsync 仅物化工作树，破坏性覆盖前 repo 工作树必须干净（脏则先 commit 或中止）——git 历史是恢复安全网。
- KD-2 deploy 端保持扁平 + `install-name` 硬失败策略。
- KD-3 lock v4 schema：`zone` / `source` / `commit` / `install-name` / `orphaned`；`own/` 不进 lock。
- KD-4 新源接入走现有 sources.conf 格式：addyosmani `git@github.com:addyosmani/agent-skills.git|skills|references`；diagram-design `git@github.com:cathrynlavery/diagram-design.git|skills|`（标准形态，勘误见异议 #4）。第 4 字段（根级显式名）与 find exclude 适配目录保留为通用防御加固，本期不启用。
- KD-5 doctor = 期望态对比 + 检查注册表 + 两级 repair（白名单自动 / 人工确认）。
- KD-6 bootstrap 分层 L0-L4，`hack/setup.sh --level` + doctor 验收。
- KD-7 workflow 能力槽位 + 映射表；egm 设计阶段与偏差评审插入点位固定。

### 分阶段落地（staging）

- **Stage 0（止血，当天可完成）**
  回滚 archify 本地编辑为 vendor 原样（用户裁决直接 drop 不归档：repo `git restore skills/archify/` + node 重新物化，两处同步清）；删除 `~/.deepseek/agents/` 死配置；部署 code-walk 到 `~/.agents/skills` 并补 `depends-on:` frontmatter；执行 ZCode 双读机制验证实验，结论记入 `harness/zcode/NOTES.md`。
  验收：`git status` 干净；ZCode 会话 skill 列表无重复；dsh 下 code-walk 可用。
- **Stage 1（地基）**
  双区目录迁移分批执行（egm 源试点 → 其余源；`own/` 先迁三个自研）；sources.conf 第 4 字段与 exclude；lock v4；`sync-skills.sh` 三条流（pull/backup/restore）按 KD-1 改造；重名硬失败。
  验收：单源 pull 幂等重跑无 diff；全量 restore 后 doctor static 全绿；`.skill-lock.json` 无未标注孤儿。
- **Stage 2（部署与治理）**
  四个 `harness/<name>/` 目录 + 各自 verify/healthcheck/repair；期望态清单 manifest；`hack/doctor.sh` + 检查注册表 + repair 分级；接入 addyosmani（references 复制策略 + 漂移检查）与 diagram-design（根级 pull）。
  验收：临时 HOME 模拟新机，`hack/setup.sh` 到 L3 全过，doctor 无误报。
- **Stage 3（工作流）**
  两份 workflow 文档通用化（占位符、能力槽位映射表、前置条件声明——目标项目需先经 `/setup-matt-pocock-skills` 初始化，repo 不 track 其产物）；插入 `egm-brainstorm → concepts_brief → egm-draft` 设计阶段；code-review 后接 `egm-review` / `egm-drift-report`。
  验收：文档在无 Go/GPFS 上下文的任意新项目可直接套用；映射表指向的 skill 全部存在且已部署（doctor 检查）。
- **Stage 4（可选进化，不承诺）**
  per-project skill profiles（利用 dsh project 级 `.agents/skills` rank 200 做项目级子集部署）；`depends-on` 副产品：依赖图可视化（`hack/graph.sh`）。

### 交给 egm-draft 时必须携带的未决项

1. ZCode 双读机制验证实验结论（Stage 0 产出，决定 repair 形态）。
2. `~/.gemini/config/mcp.json` 真实路径验证（可先跑一次 `sync-mcps.sh configure antigravity` 观察）。
3. addyosmani 源接入后 install-name 冲突的实况清单（预测会有重名，名单以实测为准）。
