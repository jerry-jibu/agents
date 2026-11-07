# 多 harness 智能体环境仓库的治理与进化（jerry-jibu/agents）

*   **Author:** jerry-jibu
*   **Status:** Approved（egm-review 五阶段完成：Rev.2 修 Stage 5/6/7 发现、Rev.3 修 Stage 8 发现、Rev.4 修 Stage 9 发现）
*   **Date:** 2026-11-06
*   **前置输入:** [concepts_brief.md](../../concepts_brief.md)（EGM 七视角头脑风暴产物）

--------------------------------------------------------------------------------

## Overview

`jerry-jibu/agents` 是个人智能体环境仓库，维护 skills、agents（subagent personas）、MCP 配置、workflows 四类资产，服务四个 agent 运行环境（harness）：ZCode（`~/.zcode/`）、Claude Code（`~/.claude/`）、Antigravity（`~/.gemini/`）、deepseek-harness（下称 dsh，原生读 `~/.agents/skills`，零部署即达）。本设计把它从现状——repo 只是"上游 → node live 目录 → repo"三站流转里的第三站被动备份——重构为**以 git 为唯一权威的治理单元**：vendor/in-house 双区分离、per-harness 治理目录、期望态驱动的单文件 doctor、分层 bootstrap，以及通用化的交付 workflow 模板。

## The Problem

当前仓库一个扁平 `skills/` 同时承担两种数据流方向相反的角色——上游 skills 的镜像（上游 → repo）与自研资产的 source of truth（repo → 部署）——由此产生已实测验证的缺陷：

1. **冲突 A（数据丢失类）**：`skills/archify/**` 存在本地编辑，但 archify 是 pull 源且 pull 用 `rsync -a --delete` 精确镜像，下次 pull 会静默抹掉本地改动。上游镜像与自研资产无边界。
2. **冲突 B（重复注册类）**：ZCode 同时读取 `~/.zcode/skills/`（symlinks）与 `~/.agents/skills/`（真实目录），会话中每个 skill 出现两次。
3. **冲突 C（死配置类）**：`~/.deepseek/agents/` 是对 dsh 机制的错误猜测（dsh 无个人 named-subagent 目录，subagent 是运行时委托）；`~/.gemini/config/mcp.json` 路径仍未验证。
4. **依赖不可见**：自研 skill code-walk 依赖 `archify`、`diagram-design`（teach 待正文复核），但依赖只写在 SKILL.md 正文里，frontmatter 无声明；且 code-walk 存在部署缺口（repo 有、`~/.agents/skills` 没有）。
5. **lock 历史包袱**：`.skill-lock.json`（v3，skills.sh CLI 的账本格式而非 sync-skills.sh 产物）含 7 个 lock-only 冻结条目（6 个属 sources.conf 未声明源、1 个属已声明源但上游已删），且条目只有 folder hash 与时间戳，无 commit 锚——上游版本实际锁不住。
6. **workflow 模板写死外部项目**：`docs/agents/{feature,bugfix}-workflow.md` 内嵌 Go/GPFS/issue-tracker 项目内容；其引用的配套文档（issue-tracker.md、triage-labels.md 等）属目标项目初始化产物，本 repo 不应 track。
7. **新机 setup 未定义**："导入新环境快速 setup"没有分层定义与验收标准。

问题的完整解法见 Goals G1-G8（与上列七项一一对应）。

## Goals

*   **G1 双区治理（目录规则）**：
    *   **G1a 目录归属规则**：`vendor/github.com/<owner>/<repo>/<name>/`（pull-only 上游镜像；路径由 clone URL 机械变换而来——去掉 `git@`/`https://`、`.git`、`:`→`/`，host/owner/repo 三段嵌套天然无歧义）与 `in-house/skills/<name>/`（自研，repo 即 source of truth）为顶层目录，原扁平 `skills/` 迁移后消失；16 个无归因目录冻结进 `vendor/unknown/<name>/`（冻结语义：勿手改、pull 永不触碰；条目记冻结日期，可经 adopt 通道复核——归编确认源 / 晋升 in-house / 删除退役）。
    *   **G1b 数据流权威**：git repo 是唯一权威；最新修改都进 git（repo 内编辑 → commit/push），各节点 `git pull` 后物化。**pull 仅在单一权威节点执行；其余节点只 consume（git pull + restore 物化）**——避免 vendor/lock 的跨节点合并冲突。lock 维持单文件。
    *   **G1c 破坏性 guard**：破坏性覆盖前 repo 工作树必须干净（脏则先 commit 或中止）；node 侧受 delta guard 保护——guard 以部署基线（lock 的 `deployedHash`）为参照区分"repo 合法前进"与"node 本地漂移"（见 NFR 与数据流模型）。
*   **G2 archify 止血**：本地编辑直接 drop（用户裁决，不归档），repo `git restore` + node 重新物化，两处同步清。
*   **G3 per-harness 治理目录**：`harness/<zcode|claude|antigravity|deepseek>/` 各含三件：`NOTES.md`（人读机制说明：该 harness 实际读哪里、怎么读、验证日期叙述）、`config/`（配置备份，凭据策略见 Risks）、`expected.json`（机器可读期望态 + `verifiedAt`，doctor `--live` 的唯一断言源；zcode/deepseek 的 expected.json 内含"共享根 `~/.agents/skills` 零额外部署"约定——共享根约定不另立第二期望源）。未验证路径标 experimental。
*   **G4 依赖显式化**：SKILL.md frontmatter 增加 `depends-on:` 字段（v1 只建模 skill 名依赖）。解析顺序 in-house → vendor；同名策略域：install-name 全局唯一，**in-house 与 vendor 同名时 in-house 胜出并提示，vendor↔vendor 同名硬失败**（报错指路"fork 进 in-house 改名后重试"；别名机制推迟到真发生再加）。fork 进 in-house 时记 `forked-from: <source>@<commit>`。
*   **G5 workflow 通用化**：Go/GPFS 示例模糊为占位符；模板正文**直接写 skill 名**（`/grill-with-docs`、`/to-spec` 等），头部一句"上游改名请全局替换并重跑 doctor"（slot-map 映射表与对应检查项已按裁决删除）；grill 与 to-spec 之间插入方案设计阶段（`egm-brainstorm → concepts_brief → egm-draft`）；code-review 之后接 `egm-review`/`egm-drift-report` 偏差评审；配套文档声明为 `/setup-matt-pocock-skills` 初始化的前置条件，repo 不 track 中间产物。
*   **G6 新源接入**：addyosmani/agent-skills（`|skills|references`，references 直接复制——实测 0.1MB/份 ×25 ≈ 2.5MB 上限，代价可忽略）与 cathrynlavery/diagram-design（`|skills|`，标准自含形态）。
*   **G7 健康检查与修复**：`hack/doctor.sh` **单文件交付**（函数表 + 平行索引数组即注册表——bash 3.2 无关联数组，元数据以 `check_c1_sev` 类命名约定承载；拆分条件：检查项 >15 或出现第二维护者/消费形态变化时再拆 `hack/checks/`）。doctor = 期望态对比（"期望的没有"如 dsh/zcode skills 零额外部署不报警）。repair 白名单（四处口径一致）：symlink 去重/重建、部署缺口重部署（带 delta guard）、lock 元数据补录、**in-house frontmatter 机械修**（name==dirname 校正、depends-on 键规范化；vendor/unknown 永不自动改写）。其余人工确认。
*   **G8 bootstrap 分层**：L0 结构就绪（目录 + lock 校验）→ L1 skills 部署 + 无重复注册 → L2 agents 部署 → L3 MCP 配置 + 服务存活 + **doctor static+live 全绿终检**；`hack/setup.sh [--level N]` 默认到 L3 即完成态。

## Non-Goals

*   **不做多机自动同步协议**——多节点经 git 手工纪律（commit/push/pull）协调，pull 权集中于单一权威节点（G1b）；repo 是可移植备份单元，"导入新环境"由 G8 覆盖。
*   **不做 skill 自动升级迁移工具**——pull 即升级；版本可追溯由 lock v4 commit 锚承担（每次 pull 记一个 sha 的成本）。
*   **不覆盖 harness 无法自定义的部分**（如 zcode 内置 agents）——只治理有已验证配置面的部分。
*   **不引入 git submodule 承载 vendor**、**不做 repo 直连 live store 的 symlink 方案**、**harness 目录不用点前缀命名**——理由见 Alternatives Considered。

## Open Questions & Resolved

*   **Q2'（唯一遗留）**：`~/.gemini/config/mcp.json` 与同目录 0 字节的 `mcp_config.json` 哪个是 Antigravity 实际读取的文件名。验证：开一个 Antigravity 会话看 sideshow 工具是否出现；未出现则以 `mcp_config.json` 复测。目录级证据已确认 `~/.gemini/` 为 Antigravity 真实 home（app 自建 `antigravity/` 状态目录、oauth token、`.migrated` 标记、`projects/`、`sidecars/`，及 `~/Library/Application Support/Antigravity`）。

### Resolved During Drafting（证据与处置随行）

*   **Q1 ZCode 双读机制 → 闭合**：
    *   机制：用户级 skills 发现根固定为 `~/.zcode/skills` 与 `~/.agents/skills` 两处（不可配置移除；commands 同构双根，MCP 另有 `~/.agents/mcp.json` fallback）；同名 skill 两处均被发现、`.zcode` 先于 `.agents` 遮蔽后者。
    *   实测：`~/.zcode/skills/` 全部 79 条均为指向 `~/.agents/skills/*` 的 symlink，无 zcode 独有内容。
    *   处置：整体删除 symlinks，`~/.agents/skills` 成为唯一用户级根；doctor 规则："`~/.zcode/skills` 不得含与 `~/.agents/skills` 同名的条目（默认应为空）"。commands 双根的会话级表现（重复 or 遮蔽）待一次验证后再决定是否泛化 C3——暂不泛化，结论记 `harness/zcode/NOTES.md`。
*   **Q3 addyosmani 重名 → 闭合**：repo 与 addyosmani catalog 交集 = 25 个完全同名（历史上经 skills.sh CLI 装入）；egm/mattpocock 与其零交集。处置（adopt-or-diff）：
    *   与上游 diff 干净 → 归编 `vendor/github.com/addyosmani/agent-skills/<name>`（pull 接管所有权）；
    *   有差异 → diff 呈现由作者裁决 drop（vendor 规则）或 fork 进 `in-house/skills/`；
    *   vendor↔vendor 撞名硬失败（G4）。

## Critical User Journeys (CUJs)

### CUJ 1: 新机快速导入

*   **Given**: 一台新 Mac，具备 git、SSH key 与 Node.js 运行时（sideshow 服务与 stdio MCP 依赖）；远端 `git@github.com:jerry-jibu/agents.git` 可达。
*   **When**: `git clone` 后执行 `hack/setup.sh`（默认 --level 3）。
*   **Then**: L0 目录结构与 lock 校验通过；L1 skills 物化到 `~/.agents/skills/`（共享根；per-harness 专属路径按 `expected.json`）且无重复注册；L2 agents 部署到 zcode/claude/antigravity（各 10 条，与 repo `agents/` 一致；deepseek 不适用）；L3 MCP 配置写入**已验证** harness（zcode 必做；antigravity/deepseek 在各自路径验证完成前输出 unverified、不计入验收）并以 doctor static+live 全绿终检。

### CUJ 2: 上游更新（vendor 数据流）

*   **Given**: 权威节点；`hack/sources.conf` 声明 6 个源（现有 4 + 新增 2）；repo 工作树干净。
*   **When**: `hack/sync-skills.sh pull`。
*   **Then**: 仅 `vendor/github.com/<owner>/<repo>/**` 与 `.skill-lock.json` 变化（commit 锚更新）；`in-house/` 与 `vendor/unknown/` 零变化；node 侧 delta guard 无漂移拦截（有漂移则中止并输出 adopt/discard 指引）；pull 后 `git diff` 供人工确认，`git commit + push` 发布；其他节点 `git pull` 后物化。

### CUJ 3: 自研 skill 演进（in-house 数据流）

*   **Given**: `in-house/skills/code-walk/` 含 `depends-on: archify, diagram-design, teach` frontmatter 声明（teach 待正文复核）。
*   **When**: 在 repo 内编辑后 `git commit + push`，并运行 `hack/sync-skills.sh restore code-walk`。
*   **Then**: 部署基线比对通过（node 持旧版 = 基线一致，属合法前进，guard 放行）；code-walk 物化到 `~/.agents/skills/code-walk/` 且基线更新为新版哈希；doctor 验证依赖 skill 存在且已部署；git 历史承载版本，不进 lock。

### CUJ 4: 日常健康检查

*   **Given**: repo 与 node 处于同一部署态（doctor static 绿）。
*   **When**: `hack/doctor.sh`（默认 static）或 `hack/doctor.sh --live`。
*   **Then**: 按函数表输出期望态对比报告（severity 分级）；白名单项可 `--fix` 自动修复（含 delta guard）；人工确认项列出建议命令但不执行。

### CUJ 5: 新项目套用 workflow 模板

*   **Given**: 目标项目已执行 `/setup-matt-pocock-skills` 初始化（产生 issue-tracker.md、triage-labels.md 等配套）。
*   **When**: 套用本 repo 的 feature-workflow / bugfix-workflow 模板开展开发。
*   **Then**: 全链路技能引用（grill-with-docs / egm-brainstorm→egm-draft / to-spec / to-tickets / implement / tdd / code-review / egm-review/egm-drift-report / diagnosing-bugs）均为存在且已部署的 skill 直名；Go/GPFS 等占位符按项目替换。

## Technical Plan (Architecture)

### 目标目录树

```text
agents/
├── vendor/                                # 上游镜像区，pull-only（顶层）
│   ├── github.com/<owner>/<repo>/<name>/  # 路径 = clone URL 机械变换
│   │                                      #   （mattpocock/skills、addyosmani/agent-skills、
│   │                                      #    google/elephant-goldfish-model、tt-a1i/archify、
│   │                                      #    modem-dev/sideshow、cathrynlavery/diagram-design
│   │                                      #    + lock-only 冻结仓 vercel-labs/* 等）
│   └── unknown/                           # 16 个无归因目录，冻结（勿手改、pull 不触碰、
│                                          #   FROZEN.md 记冻结日期、可经 adopt 晋升/退役）
├── in-house/                              # 自研区（顶层）
│   └── skills/<name>/                     # source of truth（code-walk/ code-to-spec/
│                                          #   architecture-diagram/ insight-diagram/，
│                                          #   git 即版本，不进 lock）
├── agents/                                # subagent personas（10 个 egm-*.md）
├── mcps/                                  # MCP service + harness-facing entries（sideshow.json：会话成果发布面板服务，兼作 MCP 链路验收哨兵）
├── harness/
│   ├── zcode/      # NOTES.md（机制叙述）+ config/（备份）+ expected.json（SSOT，verifiedAt）
│   ├── claude/     # 同构；skills 路径待一次会话验证（experimental）
│   ├── antigravity/# 同构；mcp 文件名待 Q2'
│   └── deepseek/   # 同构；skills 零部署为期望态；mcp 配置在 ~/.dsh/ 体系内待验证
├── docs/agents/                           # 通用化 workflow 模板（直写 skill 名）
├── hack/
│   ├── sources.conf      # 6 源（URL|subdir|shared_dirs）
│   ├── sync-skills.sh    # pull / collect / restore / adopt / agents / list
│   ├── sync-agents.sh    # collect → deploy（三 harness）
│   ├── sync-mcps.sh      # 服务生命周期 + 按验证结论修正的配置路径
│   ├── doctor.sh         # 单文件：函数表注册 + 期望态对比 + --fix 白名单 + --live
│   ├── attribute.sh      # 归因脚本（Stage 1 一次性迁移工具，完成即退役；"防再出现"检查归 C5）
│   └── setup.sh          # bootstrap L0-L3，每层以 doctor 为验收门
└── .skill-lock.json      # v4（单文件；仅记已声明源）
```

### 数据流模型（git 为唯一权威）

```text
上游 repos ──pull(depth-1 clone + rsync --delete)──▶ vendor/github.com/<owner>/<repo>/
   （仅权威节点；只写已声明源；覆盖前 repo 工作树必须干净）        │
                                                                ▼
in-house/skills/<name>/ ──（repo 内编辑即 git 变更）──▶ [git repo = 唯一权威]
                                                                │ commit + push（发布）
                                                                │ git pull（其他节点）
                                                                ▼
                                        setup.sh / restore（物化，非权威；delta guard 前置）
                                                                │
                                                                ▼
                              node: ~/.agents/skills/（唯一用户级 skills 根）
                                 ├─ ZCode 原生读（清空 ~/.zcode/skills symlinks 后）
                                 ├─ deepseek-harness 原生读（rank 500）
                                 └─ claude / antigravity 按 harness/<name>/ 验证结论部署
```

（物化 = 从 repo 实体**复制**到 node 目录，非 symlink。）三条流的唯一职责（原 backup 流按裁决取消对 skills 的收集）：

*   **pull**：上游 → `vendor/github.com/<owner>/<repo>/**` + lock v4（commit 锚更新）。镜像粒度钉死 **per-skill**（只 rsync 上游现存的各 skill 目录）——上游已删的遗留条目天然保留，不会被整源 `--delete` 清除。单源 clone 失败全中止；lock 写入 temp+rename 原子；中断重跑幂等收敛（单源 pull 二次执行无 diff）；**pull 写 repo 后自动对本节点执行 restore**（delta guard 在此触发）。永不触碰 `in-house/` 与 `vendor/unknown/`。
*   **collect**（node → repo）：只收 node 起源的生成管线产物——`mcps/` 与 `harness/*/config/` 备份（凭据策略见 Risks）；`agents/`（personas 生成结果）的收集由 `sync-agents.sh collect` 承担（职责切分，见实施计划条目 7b/15）。**skills 零收集**；in-house 的 node 侧漂移由 doctor C4 报告，收割走显式 `adopt`（diff 呈现 → 确认后 git-native 落盘）。
*   **restore**（repo → node）：`vendor/github.com/<owner>/<repo>/<name>/` 与 `in-house/skills/<name>/` 统一物化到 `~/.agents/skills/<install-name>/`（扁平）；harness 专属物化到各自已验证路径。**vendor 区物化时经 `lib-normalize.rb` 做 deploy 边界归一**（2026-11-07 治理精化：上游不守我们规矩的容差层——镜像保持字节忠实，仅 node 副本修复已知 strict-YAML 断裂类；in-house 不归一，源即须合规）。

**node 侧 delta guard（硬中止 + 清单指路，以部署基线为参照）**：每次物化成功后，lock v4 对应条目记录 `deployedHash`（node 目录内容哈希）作为部署基线。guard = **node 当前内容 vs 部署基线**（而非 node vs repo 当前）：基线一致 → node 无独立改动，允许覆盖（repo 合法前进，如 CUJ 3 日常流）；基线不一致 → node 存在独立改动（漂移），立即中止本次物化，输出漂移清单 + diff 摘要 + 两条出路命令（`adopt <name>` 收割进 git / 确认丢弃后重跑）；无基线记录的新目录/新机 → node 已有内容即视为漂移；`--force` 显式越过并记日志。

### 部署矩阵（每 harness 的期望态；`expected.json` 为 SSOT，本表为示意）

| Harness | Skills | Agents（personas） | MCP |
|---|---|---|---|
| zcode | **零部署**：原生读 `~/.agents/skills`（Q1 结论）；`~/.zcode/skills` 清空（79 条 symlinks 删除，实测全为符号链接） | `~/.zcode/agents/`（已验证 live） | `~/.zcode/cli/config.json` → `mcp.servers`（http entry；`~/.agents/mcp.json` 为 fallback） |
| claude | `~/.claude/skills/`——**已验证**（2026-11-07：只读自有路径，不读共享根；restore 按 expected.json 维护 symlink 农场，104 条对齐） | `~/.claude/agents/`（实测 10 条） | `~/.claude.json` → `mcpServers`（stdio） |
| antigravity | 待验证（experimental；参照 dsh/zcode 是否也读 `~/.agents/skills`） | `~/.gemini/config/agents/`（实测 10 条，与 repo 一致） | `~/.gemini/config/mcp.json`（文件名待 Q2'） |
| deepseek | **零部署**：原生读 `~/.agents/skills`（dsh 发现根优先级权重 rank：project `.agents/skills`=200 最高、`~/.dsh/skills`=400、`~/.agents/skills`=500，数值越小越优先） | **不适用**（运行时委托；无个人目录；`~/.deepseek/agents/` 死配置删除） | dsh 的 MCP 配置在 `~/.dsh/` 体系内——`~/.deepseek/mcp.json` 同属路径猜测，**待一次 dsh 会话验证**后修正 |

矩阵中"待验证"项以 `harness/<name>/NOTES.md` 叙述 + `expected.json`（含 `verifiedAt`）落地；doctor 对 `verifiedAt` 超期（>90 天）输出 warn 提示重验；验证前相关 check 输出 `unverified` 且不计退出码。

### `.skill-lock.json` v4（单文件；仅记已声明源）

```json
{
  "version": 4,
  "sources": {
    "github.com/addyosmani/agent-skills": { "url": "git@github.com:addyosmani/agent-skills.git" },
    "github.com/vercel-labs/agent-skills": { "url": "…", "frozen": true }
  },
  "skills": {
    "<install-name>": {
      "zone": "vendor",
      "source": "github.com/addyosmani/agent-skills",
      "commit": "<pull 时 depth-1 clone 的 HEAD sha>",
      "pulledAt": "<ISO8601>",
      "deployedHash": "<上次成功物化后的 node 目录内容哈希（delta guard 基线）>"
    }
  }
}
```

规则：`in-house/skills/` 不进 lock（git 即版本）；冻结 skill **条目**不进 lock，但冻结**源**在 sources 段以 `frozen: true` 登记（C5 防杂散检查的数据源）；`vendor/unknown/` 的冻结清单以 `vendor/unknown/FROZEN.md`（目录名 | 冻结日期 | 溯源注记）承载；install-name 即对象键（唯一形态）；**历史冻结条目目录名 = 现有 install-name**（保持现状等价，如 vercel-react-best-practices；"叶名即 install-name"仅约束今后 pull 的新条目）；deploy 端扁平名即 install-name。注：现 `.skill-lock.json`（v3）是 skills.sh CLI 的账本格式——v4 迁移时以 node 活 lock（`~/.agents/.skill-lock.json`）与 repo 旧拷贝双份作为**归因输入**，v3 lock 仅作输入，不是权威账本。

### doctor 引擎（单文件，期望态对比）

两态输入：期望态（各 `harness/<name>/expected.json`，共享根约定内含于 zcode/deepseek 两份）+ 实际态（repo 树、node 目录、lock、配置文件）。检查以函数表注册（`check_c1() ...` + 平行索引数组或 `check_c1_sev` 命名约定承载 severity/auto-repairable，兼容 bash 3.2）；C7 live 消费 `sync-mcps.sh status` 输出实现，`sync-agents.sh list` 降级为 doctor 的格式化视图（不独立维护断言）：

| ID | 检查 | Severity | 自动修复 |
|---|---|---|---|
| C1 | frontmatter 合法（name==目录名、depends-on 键规范）+ **strict-YAML 校验（C1b，批量 ruby）**——**分区定级：in-house=error（可修）；vendor=warn（镜像内容不自动改写，报告上游问题；物化层已归一）；unknown=warn（冻结内容不自动改写）** | error/warn | 是（仅 in-house） |
| C2 | `depends-on:` 解析：目标存在于 in-house 或 vendor **且**已部署到 node | error | 是（重部署缺口，带 delta guard） |
| C3 | 重复注册：`~/.zcode/skills` 含与 `~/.agents/skills` 同名条目（默认应为空） | error | 是（删 symlinks） |
| C4 | 部署完整性：repo（vendor+in-house 的 install-name 集）vs `~/.agents/skills` 双向差集 + **vendor 区内容漂移**（node 与 repo 比对）+ in-house node 侧漂移报告 | error/warn | 是（重部署，带 delta guard） |
| C5 | lock 一致性：lock 条目 → 已声明源 vendor 目录**单向**对应；commit 锚存在；`vendor/github.com/**` 下既非 lock 条目又非 frozen 登记的目录 = 杂散（frozen 登记 = sources 段 `frozen: true` 或所在源目录/`vendor/unknown/` 的 `FROZEN.md`；防无归因再出现） | warn | 是（lock 元数据补录） |
| C6 | 杂散目录：`~/.agents/skills` 下无 `.`/非 skill 目录 | error | 否（列举后人工确认删除） |
| C7 | MCP（`--live`）：配置存在于已验证路径、服务 handshake 存活；`expected.json` 的 `verifiedAt` 超期（>90 天）warn | error（live） | 否 |

repair 白名单（与 G7/NFR 一致）：C1（仅 in-house）、C2/C4（带 delta guard）、C3（symlink 清理，幂等无内容比对）、C5 补录；C6 及一切删除类、覆盖类操作人工确认（列出建议命令，不执行）。

### workflow 模板结构（通用化后）

两份模板各含四个通用件：(1) **占位符层**——项目特定内容（原 Go/GPFS/issue-tracker 示例）以 `{{PLACEHOLDER}}` 表达并附替换说明；(2) **前置条件块**——"目标项目需先经 `/setup-matt-pocock-skills` 初始化产生配套文档，本 repo 不 track 这些产物"；(3) **技能直名引用**——正文直接写 `/grill-with-docs`、`/to-spec` 等（上游改名请全局替换并重跑 doctor）；(4) **流程正文**——feature 流在 grill 与 spec 之间固定**方案设计阶段**（`egm-brainstorm → concepts_brief → egm-draft`），review 之后固定**偏差评审**（`egm-review` / `egm-drift-report`）；bugfix 流在方案决策处接同一设计阶段（轻量：`egm-brainstorm` 可选、破坏性方案必经），合并关闭前加轻量偏差评审（`egm-review` 单轮）。

### agents 生成-部署链（唯一链路定义）

`sync-skills.sh agents`（从各 skill 的 `agents/*.md` persona frontmatter 生成 `~/.zcode/agents/`，tools 按 persona 白名单）→ `sync-agents.sh collect`（收进 repo `agents/`）→ `sync-agents.sh deploy`（**zcode/claude/antigravity 三 harness；deepseek 目标移除**——dsh 无个人 agents 目录）。`sync-mcps.sh` 的服务生命周期（start/stop/status）与 sideshow 的 service/http/stdio 三态模型保持现状（zcode 走 http、其余 stdio 代理到 :8228），仅配置写入路径按 `harness/<name>/NOTES.md` 验证结论修正。

## Alternatives Considered

### Alternative A: vendor 用 git submodule 承载（天然锁版本）

*   **Pros**: 上游版本即 git 对象，`git submodule update` 即精确回放；无需自建 lock schema。
*   **Cons**: 个人仓库场景心智负担重（init/update/absent-module 状态机）；六源 × 104 个 skill 目录的拆分粒度与 submodule 的整仓模型不匹配；与 pull/collect/restore 三流完全不兼容。
*   **Reason for Rejection**: 版本可追溯由 lock v4 commit 锚以每次 pull 记一个 sha 的成本满足；submodule 的整仓粒度与"源内按 skill 镜像 + deploy 扁平化"冲突。

### Alternative B: repo 直接作为 live store（`~/.agents/skills` symlink 到 repo `skills/`）

*   **Pros**: 单一目录、零同步脚本、零漂移可能。
*   **Cons**: node 侧任何实验性改动直接弄脏 repo 工作树（冲突 A 机制复活）；vendor 区失去防误改屏障；与 dsh 原生读取路径耦合过深；vendor/in-house 分区在 live store 视角下无法保持（dsh 只认扁平目录）。
*   **Reason for Rejection**: 使"防误改"这一核心诉求失效；保留其洞见（repo 唯一权威、node 纯部署目标）但物理分离，由物化脚本衔接。

### Alternative C: 维持扁平 `skills/` + `.gitignore` 排除 vendor 生成物

*   **Pros**: 改动最小。
*   **Cons**: vendor 内容失去备份价值；lock 与 sources.conf 失去对应物；冲突 A 无解。
*   **Reason for Rejection**: 与"repo 是可移植备份单元"定位直接矛盾；新机 bootstrap 无法恢复。

### Alternative D: doctor 写成多文件检查注册表（`hack/checks/*.sh`）

*   **Pros**: 检查项增删与引擎解耦，第三方可贡献检查。
*   **Cons**: 为预测性膨胀预建协议（当前 7 项）；单文件函数表即注册表，能力等价。
*   **Reason for Rejection**: v1 单文件交付，拆分条件写明（>15 项或第二维护者出现）。

### Alternative E: workflow 模板硬编码 mattpocock skill 名 + slot-map 映射表间接层

*   **Pros**: 映射表使改名只改一处；doctor 可持续校验映射。
*   **Cons**: 2 份模板的量级撑不起间接层（grep/sed 两文件与改一表成本相同）；模板不可直读；多一份元数据与检查项。
*   **Reason for Rejection**: 模板直写 skill 名 + 头部"全局替换"提示；上游存在改名先例，但发现时机（调用时）对个人使用可接受。

### Alternative F: harness 目录用点前缀命名（`.zcode/`）

*   **Pros**: 呼应 node 侧点前缀 home 目录惯例。
*   **Cons**: 点前缀在 git 惯例上暗示工具私有目录，与人工治理资产语义相反；ls 默认不可见。
*   **Reason for Rejection**: `harness/<name>/` 表达一等治理对象。

### Alternative G: addyosmani `references/` 部署期路径改写（不复制，改写 SKILL.md 内引用）

*   **Pros**: 零复制；上游单 skill 安装的 references 路径断裂问题（addyosmani/agent-skills issue #361）在部署侧规避。
*   **Cons**: 改写上游内容违反 vendor 精确镜像原则（漂移检查失效）；每源一套改写规则。
*   **Reason for Deferral**: v1 直接复制 references（实测 0.1MB/份 ×25 ≈ 2.5MB 上限，代价可忽略）+ doctor 漂移检查；路径改写与 repo 单份 `_shared/` 存储均列为 future work。

--------------------------------------------------------------------------------

## Non-Functional Requirements

*   **可恢复性（核心，含 node 侧）**: 一切破坏性操作前——repo 工作树干净 guard（脏则先 commit 或中止）与 node 侧 delta guard（以 lock `deployedHash` 基线判定漂移，漂移即硬中止 + adopt/discard 指引；基线一致的合法前进直接放行）——git 历史与 guard 机制共同构成回滚方案；guard 是机制，不依赖操作者习惯。
*   **可移植性**: 所有 `hack/` 脚本保持 macOS bash 3.2 兼容（空数组展开用 `${arr[@]+"${arr[@]}"}`）；rsync 源参数尾斜杠语义在脚本内注释钉死。
*   **误报控制**: 期望态使"期望的没有"（dsh/zcode skills 零额外部署）不报警；未验证路径输出 `unverified` 且不影响退出码。
*   **爆炸半径**: repair 白名单仅限幂等操作（带 delta guard）；删除类、覆盖类一律人工确认。

## Risks & Mitigations

*   **供应链（上游 SKILL.md 即代理指令，直通 4 harness）**: pull 后人工 `git diff` 审查是主缓解；单人仓库风险自留（接受）。锚一致性不设自动拦截（pull 即取 HEAD 写锚，该条件恒真无操作意义）。
*   **凭据入 git 历史（后删无用）**: collect 前扫描配置文件，含凭据样字段（`env`/`headers`/`*token*`/`*key*`）的**整个文件不进 repo**，doctor warn 提示手工脱敏后再加入。现状实测：sideshow 两条 entry 零凭据。
*   **多节点并发**: pull 权集中于单一权威节点（G1b 规则约束；lock 单文件的残余冲突面以此规则闭合）。
*   **harness 行为漂移**: `expected.json` 的 `verifiedAt` 超期（>90 天）warn，提示重验（C7）。
*   **lock/树漂移**: pull 原子性（temp+rename、单源失败全中止）+ C5 一致性检查。
*   **上游不守本 repo 规约**（如 mattpocock 的 description 未加引号，strict-YAML 解析器丢弃该 skill）: 镜像容忍（字节忠实）+ 物化层归一（`lib-normalize.rb` 修复已知断裂类）+ doctor C1b 持续检测（vendor 区 warn）；新断裂类出现时先人工确认再扩 normalizer 范围。
*   **node 侧未收割改动丢失**: delta guard 硬中止 + adopt 显式收割通道。

## Future Improvements

*   **per-project skill profiles**: 利用 dsh 项目级 `.agents/skills`（rank 200）与 ZCode workspace `.zcode/skills` 做项目级 skill 子集部署。
*   **依赖图可视化**: `depends-on:` 数据的副产品——`hack/graph.sh` 输出 skill 依赖 mermaid 图。
*   **references repo 单份 `_shared/` 存储 + 物化期展开**（若体积增长超阈值）；**路径改写**（Alternative G）。
*   **doctor 拆分为 `hack/checks/` 注册表**（触发条件：检查项 >15 或第二维护者）。
*   **install-name 别名机制**（触发条件：首次 vendor↔vendor 撞名）；**quarantine 隔离转存 flag**（触发条件：delta guard 中止频率过高）。
*   **workflow 模板的 harness 分发**: 模板作为 skill 或 AGENTS.md 片段投放（当前 docs/ 存档 + 手动套用）。

--------------------------------------------------------------------------------

## Detailed Implementation Plan

按 Stage 0-3 分批推进（每 Stage 独立验收，失败可停在批次边界）。doctor v0（static 子集）提前至 Stage 1 交付，使批次验收门从 Stage 1 起为真。

### Stage 0：止血（当天可完成，无结构变更；**执行序固定为 1 → 4 → 2 → 3 → 5**——restore 类操作先于两处清理，避免旧脚本尾钩复活已删状态；条目 7 落地前禁止再跑旧 pull/restore/snapshot/agents）

#### 1. archify 本地编辑回滚（repo + node 两处同步清）

*   **Type / Scope**: repo 工作树回滚 + node 重新物化。
*   **Proposed Changes**: 执行前以 `git status --porcelain` 实测脏目录清单为准（当前仅 `skills/archify/`）；repo 侧 `git restore skills/archify/`（drop 本地编辑，用户裁决不归档）；node 侧以直连 rsync 重新物化（`rsync -a --delete`，绕开旧 restore 尾钩）。若 archify-review/tuning 亦有脏改动 → 逐目录经作者确认后处置，不自动外推 drop 裁决。

#### 2. `~/.zcode/skills/` 清理（Delete，node 侧；在条目 4 之后执行）

*   **Proposed Changes**: 删除全部 79 条 symlinks（实测全为符号链接，零非链接内容，Q1 结论）；`~/.agents/skills` 成为 ZCode 唯一用户级 skills 根。**验收**: 新开 ZCode 会话，skill 列表每名只出现一次。

#### 3. `~/.deepseek/agents/` 死配置删除（Delete，node 侧；在条目 4 之后执行）

*   **Proposed Changes**: `rm -rf ~/.deepseek/agents/`（依据冲突 C：dsh 无个人 agents 目录，subagent 为运行时委托）；验收见 Verification Plan Stage 0。

#### 4. `skills/code-walk/SKILL.md`（Modify）

*   **Proposed Changes**: frontmatter 增加 `depends-on: archify, diagram-design, teach`（teach 判定标准：正文显式调用 `/teach` 才算依赖，仅提及不算；当前正文无显式调用，预期删除 teach）；随后以直连 rsync 物化补部署缺口（`rsync -a --delete skills/code-walk/ ~/.agents/skills/code-walk/`——不触发旧 restore 尾钩）。验收见 Verification Plan Stage 0。

#### 5. `harness/zcode/NOTES.md`（Create）

*   **Proposed Changes**: 记录 Q1 结论——双根发现序、遮蔽行为、commands 同构双根与 MCP fallback、`~/.zcode/skills` 期望态为空、验证日期与本机证据；附带一次性验证 commands 双根的会话级表现（重复 or 遮蔽），结论记入本文件，作为是否泛化 C3 的依据。

### Stage 1：双区迁移与同步流改造（交织顺序：条目 7(a)(c) 骨架 + 条目 8 schema 先行 → 条目 6 三步 → 条目 9 doctor v0 → 条目 10 README；条目 6 每步验收挂在对应切片上）

#### 6. `skills/` 顶层重构（git mv 批量，egm 试点先行三步走；归因矩阵已闭合）

*   **Type / Scope**: 目录结构。
*   **归因矩阵**（实测：node 活 lock + repo 旧 lock 双账本 + 各上游 depth-1 clone 交叉验证，104 目录全量封闭）：

| 数量 | 去向 |
|---|---|
| 39 mattpocock/skills（上游现存，嵌套布局；含 software-factory；resolving-merge-conflicts 不在此列——上游已删，归 lock-only） | `vendor/github.com/mattpocock/skills/` |
| 25 addyosmani/agent-skills（上游现存） | `vendor/github.com/addyosmani/agent-skills/`（Stage 2 adopt-or-diff 复核） |
| 7 egm-* | `vendor/github.com/google/elephant-goldfish-model/` |
| 3 archify*（本地编辑先行 drop 回滚） | `vendor/github.com/tt-a1i/archify/` |
| 7 lock-only 冻结（vercel-react-best-practices、web-design-guidelines、find-skills、fireworks-tech-graph、modern-web-guidance、resolving-merge-conflicts、skill-creator；条目不进 lock，源以 `frozen: true` 登记于 sources 段；目录名 = 现有 install-name） | 对应 `vendor/github.com/<owner>/<repo>/`（R-M-C 虽在活动源 mattpocock/skills 下，per-skill 镜像粒度保证 pull 不删它） |
| 2 sideshow 源（sideshow、launch-video——上游 skills/ 实测恰为此二者） | `vendor/github.com/modem-dev/sideshow/` |
| 1 diagram-design | `vendor/github.com/cathrynlavery/diagram-design/` |
| 4 自研（code-walk、code-to-spec、architecture-diagram、insight-diagram） | `in-house/skills/` |
| 16 无归因（weather、smell、prd、prd-to-spec、to-design、ship-it、review-it、loop-it、note-it、quick-learn、modern-go、refactor、graph、explain-diff-html、simplify-codebase、test-value） | `vendor/unknown/` 冻结（FROZEN.md 记冻结日期） |

*   **Proposed Changes**: 按上表迁移，**内部显式分三步**（每步独立验收）——**第一步 egm 源试点**（shared_dirs 最复杂、agents 生成链依赖它；验收 = egm 单源 pull 幂等 + agents 链路正常）→ **第二步其余源 + lock-only 冻结 + unknown 冻结**（每源验收 = 单源 pull 幂等）→ **第三步 in-house 四自研**（验收 = restore 后四者部署可用）。迁移用 `git mv` 保留历史；迁移完成删除空的扁平 `skills/`。**vendor 内层布局钉死扁平**：`vendor/github.com/<owner>/<repo>/<install-name>/`（pull 时折叠上游分类目录，如 mattpocock 的 engineering/productivity 嵌套）；restore 反查 = lock 键（install-name）+ source 拼接路径。**部署集钉死**：vendor 全部（含 unknown 冻结与未复核的 addyosmani 目录）+ in-house——首次全量 restore 即把 node 从 79 对齐至 104。归因脚本固化为 `hack/attribute.sh`（一次性迁移工具；`vendor/unknown/FROZEN.md` 与活动源目录级 `FROZEN.md`（R-M-C 类）由它在第二步迁移时生成；Stage 1 验收通过后删除 attribute.sh，"防无归因再出现"由 C5 依 lock frozen 登记与各 FROZEN.md 检查）。附注：repo 104 vs node 79 的差集由 C4 在首次全量 restore 后收敛。

#### 7. `hack/sync-skills.sh`（Modify，核心改造）

*   **Proposed Changes**: (a) pull：目标 `vendor/github.com/<owner>/<repo>/<install-name>/`，**per-skill 镜像粒度**（折叠上游分类）；工作树干净 guard；写 repo 后自动对本节点 restore；node 侧 delta guard（deployedHash 基线判定，硬中止 + adopt/discard 指引；`--force` 显式越过并记日志）；lock temp+rename 原子写；单源失败全中止；永不触碰 `in-house/` 与 `vendor/unknown/`；(b) **backup 更名 collect 且收窄**：只收 `mcps/` 与 `harness/*/config/`（凭据文件排除 + warn），skills 零收集，`agents/` 的收集归 `sync-agents.sh collect`（职责切分）；(c) restore：分区物化（**in-house 优先于 vendor**，同名时 in-house 胜出）+ 单 skill 形态（`restore <name>`）+ delta guard；**deployedHash 算法钉死**：`find <dir> -type f ! -name .DS_Store -print0 | sort -z | xargs -0 shasum | shasum`（doctor/restore/pull 共用函数）；(d) 新增 `adopt` 子命令：diff 呈现 → 确认 → git-native 落盘（四用途：in-house 收割 / unknown 晋升 / 归编复核 / 删除退役）；(e) vendor↔vendor 撞名硬失败（指路 fork in-house 改名）；(f) 脚本头写数据流声明（git 为权威、pull 单一节点）；(g) **拆除旧机制**：移除 `ensure_dir_links`、`ZCODE_SKILLS` 与 `cmd_list` 的 `[link]` 标记（cmd_pull/cmd_snapshot/cmd_restore 三处调用点同拆——否则 C3 与 restore 互锁）；(h) `cmd_agents` 尾钩收窄为仅生成 `~/.zcode/agents/`，不再自动 collect+deploy；(i) **`snapshot` 子命令删除**（commit 语义并入 collect 后的人工 git 提交流程）。

#### 8. `.skill-lock.json`（Modify，v3 → v4）

*   **Proposed Changes**: 按 Technical Plan 的 v4 schema 重写：sources 注册段（source-id → clone URL，冻结源加 `frozen: true`）——**本条目即在 sources 段登记 addyosmani 与 diagram-design 两新源**（非 frozen；条目 14 仅改 sources.conf 并执行 adopt，消除 C5 中间态误报）；条目键 = install-name（唯一形态）、`zone/source/commit/pulledAt/deployedHash`；**初值规则**：commit = 归因时 depth-1 clone 的 HEAD，pulledAt = 迁移日，deployedHash = 首次全量 restore 后回填；skill 条目仅记已声明源；in-house 不进 lock；`vendor/unknown/FROZEN.md` 与活动源目录级 `FROZEN.md`（R-M-C 类上游已删遗留）承载冻结清单（C5 豁免数据源）；v3 双份 lock（repo 份实测更新、node 份为活账本，**并集**作为迁移归因输入）。

#### 9. `hack/doctor.sh` v0（Create，提前至本 Stage）

*   **Proposed Changes**: 单文件函数表 + 平行索引数组元数据（bash 3.2 兼容，无关联数组）；本 Stage 交付 static 子集（C1-C4、C6）作为 Stage 1 验收门——v0 的期望态为**硬编码清单**（共享根约定、zcode skills 空、repo↔node 差集规则），Stage 2 条目 12 切换为消费 expected.json（切换点即该条目）；Stage 2 补全（C5、C7 live 含凭据 warn、verifiedAt 超期）。

#### 10. `README.md`（Modify）

*   **Proposed Changes**: 目录布局、pull/collect/restore 三流与 guard、单一 pull 节点约定、doctor/setup 入口、归因矩阵摘要。

### Stage 2：per-harness 治理 + doctor 补全 + 新源（执行序：条目 14 的 sources.conf 声明与 adopt **先于**条目 12 的 C5 终检运行）

#### 11. `harness/{zcode,claude,antigravity,deepseek}/`（zcode 为扩展，其余 Create ×3）

*   **Proposed Changes**: 每目录三件：`NOTES.md`（机制叙述 + 验证日期）、`config/`（配置备份，collect 凭据排除）、`expected.json`（机器可读期望态 + `verifiedAt`，doctor `--live` 唯一断言源——live 断言统一走 expected.json，不另立 verify 脚本）。**expected.json schema 样例**（与部署矩阵 4 行一一对应）：`{"skillsRoot": "~/.agents/skills", "skillsExtra": [], "agentsDir": "~/.claude/agents", "agentsCount": 10, "mcp": {"configPath": "~/.claude.json", "key": "mcpServers", "entry": "stdio"}, "verifiedAt": "2026-11-06", "unverified": []}`（`unverified` 数组列未验证项，doctor 输出 unverified 不计退出码）。claude/antigravity/deepseek 的验证项由一次性会话补齐（claude skills 路径、antigravity mcp 文件名即 Q2'——双候选皆败时输出 unverified 不计验收、deepseek mcp 改为 NOTES.md 验证结论给出的实际路径）。

#### 12. `hack/doctor.sh` 补全

*   **Proposed Changes**: C5 lock 一致性、C7 live（MCP handshake + verifiedAt 超期 warn + collect 凭据排除的 warn 检查）、期望态消费（替换条目 9 v0 的硬编码清单）、`--fix` 白名单（含 delta guard 与 in-house frontmatter 机械修）。

#### 13. `hack/setup.sh`（Create）

*   **Proposed Changes**: `--level N`（默认 3）：L0 结构+lock 校验 → L1 skills 物化 + C3/C4/C6 绿 → L2 agents 部署（三 harness）→ L3 MCP 配置（已验证 harness）+ 服务存活 + doctor static+live 全绿终检。

#### 14. `hack/sources.conf`（Modify）+ adopt 执行

*   **Proposed Changes**: 追加 `git@github.com:addyosmani/agent-skills.git|skills|references` 与 `git@github.com:cathrynlavery/diagram-design.git|skills|`；执行 `adopt` 对 25 个 addyosmani 命名目录与 diagram-design 归编（adopt 自行 depth-1 clone 上游作为 diff 参照；diff 干净 → vendor 路径接管；diff 有差异 → 呈现 diff 由作者裁决 drop（vendor 规则）或 fork 进 in-house，Q3 处置）；pull 两新源。

#### 15. `hack/sync-agents.sh`（Modify）

*   **Proposed Changes**: HARNESSES 删 deepseek 行（含 `DEEPSEEK_AGENTS_DIR` 覆盖变量下线）、usage 文案同步；`cmd_list` 断言逻辑改为消费 doctor 输出的格式化视图（不再独立维护断言）；deploy 目标收敛为 zcode/claude/antigravity。

#### 16. `hack/sync-mcps.sh`（Modify）

*   **Proposed Changes**: 按 `harness/*/NOTES.md` 验证结论修正 deepseek（弃 `~/.deepseek/mcp.json`，改为 NOTES.md 验证结论给出的实际路径）与 antigravity（Q2' 文件名）写入路径；环境变量覆盖机制保留。（agents deploy 收敛见条目 15。）

### Stage 3：workflow 模板通用化

#### 17. `docs/agents/feature-workflow.md`（Modify）

*   **Proposed Changes**: 占位符化（`{{STACK}}`/`{{TEST_GATE}}` 等附替换说明）；前置条件块（`/setup-matt-pocock-skills` 初始化）；技能引用直写 skill 名 + 头部全局替换提示；grill 与 spec 之间插入**方案设计阶段**（`egm-brainstorm → concepts_brief → egm-draft`）；review 之后固定**偏差评审**（`egm-review`/`egm-drift-report`）。

#### 18. `docs/agents/bugfix-workflow.md`（Modify）

*   **Proposed Changes**: 同上通用化；方案决策处接设计阶段（轻量：`egm-brainstorm` 可选、破坏性方案必经）；合并关闭前加轻量偏差评审（`egm-review` 单轮）。

### Verification Plan

验收分**命令级**（机器可判）与**人工级**（需会话/人眼）两栏：

*   **Stage 0**（命令级）：`git status --porcelain` 无 archify 相关脏项；`ls ~/.zcode/skills | wc -l` = 0；`[ ! -e ~/.deepseek/agents ]`；`ls ~/.agents/skills/code-walk/SKILL.md` 存在；`harness/zcode/NOTES.md` 存在且含验证日期。（人工级）：新 ZCode 会话 skill 列表每名只出现一次；dsh 会话可见 code-walk。
*   **Stage 1**（命令级）：单源 pull 二次执行 `git status` 无 diff；首次全量 restore 后 `ls ~/.agents/skills | wc -l` = 104 且 doctor v0 static 全绿（零 error 零 warn）；lock v4 sources 段含 6 源（4 旧 + 2 新）且条目仅覆盖已声明源；扁平 `skills/` 不存在。
*   **Stage 2**（命令级）：前置 `sync-mcps.sh stop`（真机 8228 让位）；临时 HOME（`HOME=$(mktemp -d)`）下 `setup.sh` 到 L3 全过；doctor static+live 全绿（零 error 零 warn）；sideshow handshake 通过；临时 HOME `ls ~/.agents/skills | wc -l` = 104。
*   **Stage 3**（命令级）：`grep -c '{{' docs/agents/*.md` 占位符与替换说明一一对应；`grep -E 'GPFS|migrator|journalctl|etcd' docs/agents/*.md` 零命中；模板引用的 skill 直名（`grep -oE '/[a-z][a-z-]+' docs/agents/*.md` 过滤后）全部存在于已部署集。（人工级）：新项目实际套用一次。
*   **回归红线**: 每个 Stage 收尾跑一次全量 doctor static（Stage 1 起可用）+ `sync-mcps.sh status`，与上一 Stage 基线对比无新增 error。
