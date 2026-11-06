# 多 harness 智能体环境仓库的治理与进化（jerry-jibu/agents）

*   **Author:** jerry-jibu
*   **Status:** Draft
*   **Date:** 2026-11-06
*   **前置输入:** [concepts_brief.md](concepts_brief.md)（EGM 七视角头脑风暴产物，含 4 条用户裁决与 1 条勘误）

--------------------------------------------------------------------------------

## Overview

`jerry-jibu/agents` 是个人智能体环境仓库，维护 skills、agents（subagent personas）、MCP 配置、workflows 四类资产，服务四个 agent 运行环境（harness）：ZCode（`~/.zcode/`）、Claude Code（`~/.claude/`）、Antigravity（`~/.gemini/`）、deepseek-harness（原生读 `~/.agents/skills`，零部署即达）。本设计把它从"node 状态的第三站备份镜像"重构为**以 git 为唯一权威的治理单元**：双区分离上游镜像与自研资产、per-harness 治理目录、期望态驱动的健康检查（doctor）、分层 bootstrap，以及通用化的交付 workflow 模板。

## The Problem

当前仓库一个扁平 `skills/` 同时承担两种数据流方向相反的角色——上游 skills 的镜像（上游 → repo）与自研资产的 source of truth（repo → 部署）——由此产生已实测验证的缺陷：

1. **冲突 A（数据丢失类）**：`skills/archify/**` 存在本地编辑，但 archify 是 pull 源且 pull 用 `rsync -a --delete` 精确镜像，下次 pull 会静默抹掉本地改动。上游镜像与自研资产无边界。
2. **冲突 B（重复注册类）**：ZCode 同时读取 `~/.zcode/skills/`（symlinks）与 `~/.agents/skills/`（真实目录），会话中每个 skill 出现两次。
3. **冲突 C（死配置类）**：`~/.deepseek/agents/` 是对 dsh 机制的错误猜测（dsh 无个人 named-subagent 目录，subagent 是运行时委托）；`~/.gemini/config/mcp.json` 路径仍未验证。
4. **依赖不可见**：自研 skill code-walk 依赖 `archify`、`diagram-design`、`teach`，但依赖只写在正文 prose 里（SKILL.md 正文"Invoke /archify or /diagram-design"），frontmatter 无声明；且 code-walk 存在部署缺口（repo 有、`~/.agents/skills` 没有）。
5. **lock 历史包袱**：`.skill-lock.json`（v3）含 3 个 sources.conf 已删除的孤儿源条目；条目只有 folder hash 与时间戳，无 commit 锚——上游版本实际锁不住。
6. **workflow 模板写死外部项目**：`docs/agents/{feature,bugfix}-workflow.md` 内嵌 Go/GPFS/issue-tracker 项目内容；其引用的配套文档（issue-tracker.md、triage-labels.md 等）属目标项目初始化产物，本 repo 不应 track。
7. **新机 setup 未定义**："导入新环境快速 setup"没有分层定义与验收标准，一条命令做到什么程度算完成无共识。

**解法方向**（why 层面）：目录双区 + git 为权威的同步模型解决 1；per-harness 目录以"已验证机制说明"为第一公民解决 2/3；`depends-on:` 显式化 + doctor 解决 4/5；模板通用化 + 前置条件声明解决 6；bootstrap 分层 L0-L4 解决 7。

## Goals

*   **G1 双区治理**：`skills/vendor/<source>/<name>/`（pull-only 上游镜像）与 `skills/own/<name>/`（自研，repo 即 source of truth）顶层分离；数据流以 git 为权威——节点更新走 `git commit`/`push`，其他节点 `git pull` 后物化；pull 只写 `vendor/`，永不触碰 `own/`；破坏性覆盖前 repo 工作树必须干净（脏则先 commit 或中止）。
*   **G2 archify 止血**：本地编辑直接 drop（用户裁决，不归档），repo `git restore skills/archify/` + node 重新物化，两处同步清。
*   **G3 per-harness 治理目录**：`harness/<zcode|claude|antigravity|deepseek>/` 各含部署产物、配置备份（mcp.json 等）、harness 专属资产（commands/hooks 等仅特定 harness 有意义的）三类内容；每个 harness 配 verify / healthcheck / repair；目录第一公民是"已验证机制说明"（该 harness 实际读哪里、怎么读、验证日期），未验证路径标注 experimental。
*   **G4 依赖显式化**：SKILL.md frontmatter 增加 `depends-on:` 字段（v1 只建模 skill 名依赖；解析顺序 own → vendor，同名 own 优先并提示）。
*   **G5 workflow 通用化**：Go/GPFS 示例模糊为占位符；grill 与 to-spec 之间插入方案设计阶段（`egm-brainstorm → concepts_brief → egm-draft`）；code-review 之后接 `egm-review`/`egm-drift-report` 偏差评审；外部 skill 依赖用能力槽位 + slot→skill 映射表表达；配套文档声明为 `/setup-matt-pocock-skills` 初始化的前置条件，repo 不 track 中间产物。
*   **G6 新源接入**：addyosmani/agent-skills（`|skills|references`，references 复制策略 + 漂移检查）与 cathrynlavery/diagram-design（`|skills|`，标准自含形态）。
*   **G7 健康检查与修复**：`hack/doctor.sh` = 期望态对比（非绝对规则，dsh 零部署是期望态）+ 检查注册表（`hack/checks/*.sh`，每项带 severity 与 auto-repairable 标志）；repair 两级——白名单自动修（去重/重建 symlink、补部署缺口、frontmatter 小修）与人工确认（删死配置、回滚 vendor、任何覆盖 node 本地改动的操作）。
*   **G8 bootstrap 分层**：L0 结构就绪（目录 + lock 校验）→ L1 skills 部署 + 无重复注册 → L2 agents 部署 → L3 MCP 配置 + 服务存活 → L4 workflow 文档投放；`hack/setup.sh [--level N]` 默认到 L3，doctor 作为每层验收门。

## Non-Goals

*   **不做多机同步/冲突合并**——repo 是可移植备份单元，单机为主；"导入新环境"由 G8 bootstrap 分层覆盖，不需要双向同步协议。
*   **不做 skill 自动升级迁移工具**——pull 即升级；版本可追溯由 lock v4 commit 锚补强（"回到上游哪个版本"可回答），不做 diff 迁移器。
*   **不覆盖 harness 无法自定义的部分**（如 zcode 内置 agents）——只治理有已验证配置面的部分。
*   **不引入 git submodule 承载 vendor**、**不做 repo 直连 live store 的 symlink 方案**、**harness 目录不用点前缀命名**（`.zcode/` 形态否决，理由见 Alternatives Considered）。

## Open Questions

*   **Q2'（唯一遗留，阻塞 antigravity MCP 配置备份定稿）**：`~/.gemini/config/mcp.json` 与同目录 0 字节的 `mcp_config.json`（同日创建）哪个是 Antigravity 实际读取的文件名。验证：开一个 Antigravity 会话看 sideshow 工具是否出现；未出现则以 `mcp_config.json` 复测。目录级证据已确认 `~/.gemini/` 为 Antigravity 真实 home（app 自建 `antigravity/` 状态目录、oauth token、`.migrated` 标记、`projects/`、`sidecars/`，及 `~/Library/Application Support/Antigravity`）。

### Drafting 期间已闭合（证据与处置随行）

*   **Q1 ZCode 双读机制 → 闭合（官方文档 + 实测）**：ZCode 用户级 skills 发现根固定为 `~/.zcode/skills` 与 `~/.agents/skills` 两处（不可配置移除；commands 同构双根 `~/.zcode/commands` / `~/.agents/commands`，MCP 另有 `~/.agents/mcp.json` fallback）；同名 skill 两处均被发现、`.zcode` 先于 `.agents` 遮蔽后者——此即每 skill 出现两次的机制。实测 `~/.zcode/skills/` 全部条目均为指向 `~/.agents/skills/*` 的 symlink，无任何 zcode 独有内容。**处置**：整体删除 `~/.zcode/skills/` 下 symlinks，`~/.agents/skills` 成为唯一用户级根（ZCode 与 dsh 原生双读同一根）；doctor 期望态规则："`~/.zcode/skills` 不得含与 `~/.agents/skills` 同名的条目（默认应为空）"。
*   **Q3 addyosmani 重名 → 闭合（本地计算）**：repo 扁平 `skills/` 与 addyosmani catalog 交集 = 25 个完全同名——addyosmani 全目录已历史上经 vercel skills CLI 装入（lock 孤儿条目来源），node 侧同样 25 个；egm/mattpocock 与其零交集（code-review-and-quality vs code-review、test-driven-development vs tdd）。**处置**：迁移增加 adopt-or-diff 步骤——25 个同名目录及手工放入的 diagram-design 与上游 diff：干净 → 归编 `vendor/addyosmani/<name>`（pull 接管所有权）；有差异 → diff 呈现由作者裁决 drop（vendor 规则）或 fork 进 `own/`；跨源 install-name 撞名 = 硬失败 + 提示别名的守卫不变。

## Critical User Journeys (CUJs)

### CUJ 1: 新机快速导入

*   **Given**: 一台新 Mac，具备 git 与 SSH key；远端 `git@github.com:jerry-jibu/agents.git` 可达。
*   **When**: `git clone` 后执行 `hack/setup.sh`（默认 --level 3）。
*   **Then**: L0 目录结构与 lock 校验通过；L1 skills 部署到 `~/.agents/skills/` 且无重复注册；L2 agents 部署到各 harness；L3 MCP 配置写入各 harness 且 sideshow 服务存活（handshake 通过）；`hack/doctor.sh` static 全绿、无误报；L4 workflow 模板就位可选用。

### CUJ 2: 上游更新（vendor 数据流）

*   **Given**: `hack/sources.conf` 声明 6 个源；repo 工作树干净。
*   **When**: `hack/sync-skills.sh pull`。
*   **Then**: 仅 `skills/vendor/<source>/**` 与 `.skill-lock.json` 变化（commit 锚更新）；`skills/own/` 零变化；若工作树脏则中止并提示先 commit；pull 后 `git diff` 供人工确认，`git commit + push` 发布；其他节点 `git pull` 后物化到 node。

### CUJ 3: 自研 skill 演进（own 数据流）

*   **Given**: `skills/own/code-walk/` 含 `depends-on: archify, diagram-design, teach` frontmatter 声明。
*   **When**: 编辑后运行部署命令。
*   **Then**: code-walk 物化到 `~/.agents/skills/code-walk/`；doctor 验证三个依赖 skill 存在且已部署；git 历史承载版本，不进 lock。

### CUJ 4: 日常健康检查

*   **When**: `hack/doctor.sh`（默认 static）或 `hack/doctor.sh --live`。
*   **Then**: 按检查注册表输出期望态对比报告（severity 分级）；白名单项可 `--fix` 自动修复；人工确认项列出建议命令但不执行。

### CUJ 5: 新项目套用 workflow 模板

*   **Given**: 目标项目已执行 `/setup-matt-pocock-skills` 初始化（产生 issue-tracker.md、triage-labels.md 等配套）。
*   **When**: 套用本 repo 的 feature-workflow / bugfix-workflow 模板开展开发。
*   **Then**: 全链路 skill 槽位（grill / 方案设计 / spec / tickets / implement / tdd / code-review / 偏差评审）在映射表中均有指向存在且已部署的 skill；Go/GPFS 等占位符按项目替换。

## Technical Plan (Architecture)

### 目标目录树

```text
agents/
├── skills/
│   ├── vendor/<source>/<name>/   # 上游镜像，pull-only（egm/ mattpocock/ archify/
│   │                              #   sideshow/ addyosmani/ diagram-design/ 六源）
│   └── own/<name>/                # 自研 source of truth（code-walk/ code-to-spec/
│                                  #   architecture-diagram/，git 即版本，不进 lock）
├── agents/                        # subagent personas（现有 10 个 egm-*.md，链路不变）
├── mcps/                          # MCP service + harness-facing entries（sideshow.json 等）
├── harness/
│   ├── zcode/                     # NOTES.md（已验证机制）+ config 备份 + verify.sh
│   ├── claude/                    # 同构；skills 路径待一次会话验证（见部署矩阵）
│   ├── antigravity/               # 同构；mcp 文件名待 Q2' 验证
│   └── deepseek/                  # 同构；skills 零部署为期望态；mcp 配置路径待验证
├── docs/agents/                   # 通用化 workflow 模板 + slot→skill 映射表
├── hack/
│   ├── sources.conf               # 追加 2 源（现有格式即可）
│   ├── sync-skills.sh             # 分区化 pull/backup/restore + adopt-or-diff + 撞名硬失败
│   ├── sync-agents.sh             # 流程不变（collect → deploy 四 harness）
│   ├── sync-mcps.sh               # 按 harness/*/NOTES.md 修正后的路径配置
│   ├── doctor.sh                  # 期望态引擎 + 检查注册表驱动
│   ├── checks/*.sh                # 检查注册表（每项带 severity / auto-repairable 元数据）
│   └── setup.sh                   # bootstrap L0-L4，每层以 doctor 为验收门
└── .skill-lock.json               # v4 schema（见下）
```

### 数据流模型（git 为唯一权威）

```text
上游 repos ──pull(depth-1 clone + rsync --delete)──▶ skills/vendor/<source>/
   （只写 vendor/，覆盖前 repo 工作树必须干净）              │
                                                            ▼
skills/own/<name>/ ──（编辑即 repo 变更）──────────▶ [git repo = 唯一权威]
                                                            │ git commit + push（发布）
                                                            │ git pull（其他节点获取）
                                                            ▼
                                        setup.sh / restore（物化工作树，非权威）
                                                            │
                                                            ▼
                              node: ~/.agents/skills/（唯一用户级 skills 根）
                                 ├─ ZCode 原生读（清空 ~/.zcode/skills symlinks 后）
                                 ├─ deepseek-harness 原生读（rank 500）
                                 └─ claude / antigravity 按 harness/<name>/ 验证结论部署
```

三条同步流的分区规则（写入脚本头与 README）：

*   **pull**：上游 → `vendor/<source>/**` + lock v4（commit 锚更新）；工作树脏则中止；`own/` 永不被触碰。
*   **backup**（node → repo）：只收 `own/` 的 node 侧变更、`agents/`、`mcps/`、`harness/*/config/` 备份；vendor 区不收（vendor 的权威在上游 + pull）。
*   **restore**（repo → node）：分区执行——vendor+own 统一物化到 `~/.agents/skills/<install-name>/`（扁平）；harness 专属物化到各自已验证路径。

### 部署矩阵（每 harness 的期望态）

| Harness | Skills | Agents（personas） | MCP |
|---|---|---|---|
| zcode | **零部署**：原生读 `~/.agents/skills`（Q1 结论）；`~/.zcode/skills` 清空（symlinks 删除） | `~/.zcode/agents/`（已验证 live） | `~/.zcode/cli/config.json` → `mcp.servers`（http entry） |
| claude | `~/.claude/skills/`——**待一次会话验证**（experimental） | `~/.claude/agents/` | `~/.claude.json` → `mcpServers`（stdio） |
| antigravity | 待验证（experimental；参照 dsh/zcode 是否也读 `~/.agents/skills`） | `~/.gemini/config/agents/`（已写入 12 条，待验证） | `~/.gemini/config/mcp.json`（文件名待 Q2'） |
| deepseek | **零部署**：原生读 `~/.agents/skills`（rank 500） | **无个人目录**（运行时委托）；`~/.deepseek/agents/` 死配置删除 | dsh 的 MCP 配置在 `~/.dsh/` 配置体系内——`~/.deepseek/mcp.json` 同属路径猜测，**待一次 dsh 会话验证**后修正 |

矩阵中"待验证"项均以 `harness/<name>/NOTES.md`（机制说明 + 验证日期）为第一公民落地；验证前相关 check 输出 `unverified` 状态而非 `failed`，不计入 doctor 退出码。

### `.skill-lock.json` v4 schema（伪代码）

```json
{
  "version": 4,
  "sources": ["egm", "mattpocock", "archify", "sideshow", "addyosmani", "diagram-design"],
  "skills": {
    "<install-name>": {
      "zone": "vendor",
      "source": "addyosmani",
      "commit": "<pull 时 depth-1 clone 的 HEAD sha>",
      "pulledAt": "<ISO8601>",
      "orphaned": false
    }
  }
}
```

规则：`own/` 不进 lock（git 即版本）；孤儿源历史条目（vercel-labs/*、fireworks-tech-graph）保留 provenance 并标 `orphaned: true`；deploy 端扁平名即 `install-name`，跨源同名硬失败并提示手动指定别名。

### doctor 引擎（期望态对比）

两态输入：**期望态清单**（per harness：应有什么、什么是期望的"没有"——如 dsh/zcode skills 零额外部署）+ **实际态**（repo 树、node 目录、lock、配置文件）。检查项注册在 `hack/checks/*.sh`，每项声明 severity（error/warn/info）与 auto-repairable 标志：

| ID | 检查 | Severity | 自动修复 |
|---|---|---|---|
| C1 | 每个 SKILL.md frontmatter 合法（name/description 存在且 name == 目录名） | error | 否（报告） |
| C2 | `depends-on:` 依赖解析：目标存在于 own/ 或 vendor/ **且**已部署到 node | error | 是（重部署缺口） |
| C3 | 重复注册：`~/.zcode/skills` 含与 `~/.agents/skills` 同名条目（默认应为空） | error | 是（删 symlinks） |
| C4 | 部署完整性：repo(vendor+own 的 install-name 集) vs `~/.agents/skills` 双向差集 | error/warn | 是（重部署） |
| C5 | lock 一致性：条目 ↔ vendor 目录一一对应；commit 锚存在；orphaned 标注正确 | warn | 否 |
| C6 | 杂散目录：`~/.agents/skills` 下无 `.`/非 skill 目录 | error | 是（列出后人工确认删除） |
| C7 | MCP：各 harness 配置存在于已验证路径；`--live` 时服务 handshake 存活 | error（live） | 否 |
| C8 | workflow 映射表：slot 指向的 skill 存在且已部署 | warn | 否 |

repair 分级：白名单自动修 = C2/C3/C4 的重部署与去重、C6 列举；人工确认 = 删死配置、回滚 vendor、任何覆盖 node 本地改动的操作（以建议命令呈现，不执行）。

### workflow 模板结构（通用化后）

两份模板各含四个通用件：(1) **占位符层**——项目特定内容（原 Go/GPFS/issue-tracker 示例）以 `{{PLACEHOLDER}}` 表达并附替换说明；(2) **前置条件块**——"目标项目需先经 `/setup-matt-pocock-skills` 初始化（产生 issue-tracker.md / triage-labels.md / CONTEXT.md 等配套），本 repo 不 track 这些产物"；(3) **能力槽位映射表**——slot（grill / design / spec / tickets / implement / tdd / review / drift / diagnose）→ 当前 skill 名（grill-with-docs · egm-brainstorm→egm-draft · to-spec · to-tickets · implement · tdd · code-review · egm-review/egm-drift-report · diagnosing-bugs），上游改名时只改表不改流程；(4) **流程正文**——feature 流在 grill 与 spec 之间固定"方案设计阶段"（egm-brainstorm → concepts_brief → egm-draft），review 之后固定"偏差评审"（egm-review / egm-drift-report）；bugfix 流在诊断与实现间复用同一 design 槽位（轻量：egm-brainstorm 可选）。

### 不变部分

`agents/` 的生成-采集-部署链（`sync-skills.sh agents` → collect → 四 harness deploy）、`sync-mcps.sh` 的服务生命周期（start/stop/status）与 sideshow 的 service/http/stdio 三态模型（zcode 走 http、其余 stdio 代理到 :8228）保持现状，仅配置路径按验证结论修正。

## Alternatives Considered

### Alternative A: vendor 用 git submodule 承载（天然锁版本）

*   **Pros**: 上游版本即 git 对象，`git submodule update` 即精确回放；无需自建 lock schema。
*   **Cons**: 个人仓库场景心智负担重（init/update/absent-module 状态机）；六源 × 79 skills 的拆分粒度与 submodule 的整仓模型不匹配（同一源内按 skill 粒度镜像）；与现有 pull/backup/restore 三流完全不兼容，需推倒重写。
*   **Reason for Rejection**: Rejected by author: 版本可追溯的诉求由 lock v4 的 commit 锚（pull 时记录 depth-1 clone HEAD sha）以近乎零成本满足；submodule 的整仓粒度与本方案"源内按 skill 镜像 + deploy 扁平化"冲突。

### Alternative B: repo 直接作为 live store（`~/.agents/skills` symlink 到 repo `skills/`）

*   **Pros**: 单一目录、零同步脚本、零漂移可能；结构最简。
*   **Cons**: node 侧任何实验性改动直接弄脏 repo 工作树（正是冲突 A 的机制复活）；vendor 区失去防误改屏障；与 dsh 原生读取路径耦合过深，换 harness 或换机器时脆弱；repo 内 vendor/own 分区在 live store 视角下无法保持（dsh 只认扁平目录）。
*   **Reason for Rejection**: Rejected by author: 该方案把"防误改"这个核心诉求消灭掉了；保留其洞见——repo 是唯一权威、node 是纯部署目标——但物理上分离（repo 分区树 vs node 扁平树），由物化脚本衔接。

### Alternative C: 维持扁平 `skills/` + `.gitignore` 排除 vendor 生成物

*   **Pros**: 改动最小，`sync-skills.sh` 几乎不动。
*   **Cons**: vendor 内容失去备份价值（gitignore 后 repo 不再是完整备份单元）；lock 与 sources.conf 失去对应物；冲突 A（archify 本地编辑被 pull 抹掉）无解——脏与干净的边界仍在目录之外。
*   **Reason for Rejection**: Rejected by author: 与"repo 是可移植备份单元"的定位直接矛盾；新机 bootstrap 也无法从 gitignore 的内容恢复。

### Alternative D: doctor 写成单体脚本

*   **Pros**: 单文件交付快，无目录结构开销。
*   **Cons**: 检查项随 harness 与资产类型必然膨胀（当前已 8 项，映射表/MCP/agents 检查在路上），单体会演化成不可维护的 if-else 塔；severity 与 auto-repairable 元数据无处声明，repair 分级退化为脚本内散落判断。
*   **Reason for Rejection**: Rejected by author: 检查注册表（`hack/checks/*.sh` + 元数据头）以极小的结构成本换取检查项的可增删与 doctor 引擎的稳定性。

### Alternative E: workflow 模板硬编码 mattpocock skill 名

*   **Pros**: 文档直读直用，无间接层。
*   **Cons**: 上游改名/改行为即断链，而我们不控制上游（mattpocock skills 已经历过大版本演进）；模板每处引用都要跟着改。
*   **Reason for Rejection**: Rejected by author: 能力槽位 + slot→skill 映射表把外部依赖收敛到一张表，上游变化只改表；doctor 的 C8 检查还能持续验证映射有效性。

### Alternative F: harness 目录用点前缀命名（`.zcode/`、`.deepseek/`）

*   **Pros**: 呼应各 harness 在 node 侧的点前缀 home 目录惯例，直觉映射。
*   **Cons**: 点前缀在 git repo 惯例上暗示机器生成/工具私有目录（如 `.git/`、`.zcode-plugin/`），与"人工治理的资产目录"语义相反；ls 默认不可见，降低可发现性。
*   **Reason for Rejection**: Rejected by author: `harness/<name>/` 显式表达这是 repo 的一等治理对象而非工具私有产物。

### Alternative G: addyosmani `references/` 部署期路径改写（不复制，改写 SKILL.md 内引用）

*   **Pros**: 零复制放大，repo 体积最优；上游 #361 的断链问题在部署侧根治。
*   **Cons**: 改写上游 skill 内容违背 vendor"精确镜像"原则（镜像不再可比对、漂移检查失效）；每个源一种改写规则，复杂度随源数线性增长。
*   **Reason for Rejection**: Deferred by author: v1 接受 shared_dirs 复制策略（egm 源已验证同构方案）+ doctor 增加"共享树与上游漂移"检查；路径改写列为 future work，不阻塞本期。

--------------------------------------------------------------------------------

## Non-Functional Requirements

*   **可恢复性（核心）**: 一切破坏性操作（pull 的 `rsync --delete`、restore、archify drop）发生前 repo 工作树必须干净——git 历史即回滚方案；脚本以 guard 强制，不依赖操作者记忆。
*   **可移植性**: 所有 `hack/` 脚本保持 macOS bash 3.2 兼容（空数组展开用 `${arr[@]+"${arr[@]}"}` 惯例）；rsync 源参数尾斜杠语义在脚本内注释钉死。
*   **误报控制**: doctor 的期望态清单使"期望的没有"（dsh/zcode skills 零额外部署）不报警；未验证路径输出 `unverified` 且不影响退出码。
*   **爆炸半径**: repair 白名单自动修仅限幂等操作（重建 symlink、重部署缺口）；删死配置、回滚 vendor 一律人工确认（呈现建议命令，不执行）。

## Future Improvements

*   **per-project skill profiles**: 利用 dsh 项目级 `.agents/skills`（rank 200）与 ZCode workspace `.zcode/skills` 做项目级 skill 子集部署。
*   **依赖图可视化**: `depends-on:` 数据的副产品——`hack/graph.sh` 输出 skill 依赖 mermaid 图。
*   **addyosmani references 部署期路径改写**: 替代复制策略（见 Alternative G 的 Deferred）。
*   **workflow 模板槽位的 harness 分发**: 模板作为 skill 或 AGENTS.md 片段投放到各 harness（当前仅 docs/ 存档 + 手动套用）。

--------------------------------------------------------------------------------

## Detailed Implementation Plan

按 Stage 0-3 分批组织（对应 concepts_brief 的 staging；Stage 4 是 Future Improvements，不在本期）。每个 Stage 有独立验收，失败可停在批次边界。

### Stage 0：止血（当天可完成，无结构变更）

#### 1. `skills/archify/**`（git restore，node 重物化）

*   **Type / Scope**: repo 工作树回滚 + node 重新物化。
*   **Proposed Changes**: repo 侧 `git restore skills/archify/`（drop 全部本地编辑，用户裁决）；node 侧从 repo 重新物化 `~/.agents/skills/archify*`（覆盖带本地编辑的副本）。两处同步清，防 backup 流把残留带回。**前置 guard**: 执行前 `git status` 确认只有 archify 相关改动会被丢弃。

#### 2. `~/.zcode/skills/`（node 侧清理）

*   **Type / Scope**: node 目录操作（非 repo 文件）。
*   **Proposed Changes**: 删除 `~/.zcode/skills/` 下全部 79 条 symlinks（实测零非链接内容，Q1 结论）；`~/.agents/skills` 成为 ZCode 唯一用户级 skills 根。**验收**: 新开 ZCode 会话，skill 列表每名只出现一次。

#### 3. `~/.deepseek/agents/`（node 侧清理）

*   **Type / Scope**: node 目录操作。
*   **Proposed Changes**: 删除死配置目录（dsh 无个人 named-subagent 目录，subagent 为运行时委托）。

#### 4. `skills/code-walk/SKILL.md`（Modify）

*   **Type / Scope**: 自研 skill frontmatter。
*   **Proposed Changes**: frontmatter 增加 `depends-on: archify, diagram-design, teach`（以正文实际引用复核后定稿）；随后部署 `skills/code-walk/` → `~/.agents/skills/code-walk/`（补部署缺口）。**验收**: dsh/新会话可见 code-walk。

#### 5. `harness/zcode/NOTES.md`（Create）

*   **Type / Scope**: 机制说明文档（该目录的第一块内容）。
*   **Proposed Changes**: 记录 Q1 结论——双根发现序（`~/.zcode/skills` 先于 `~/.agents/skills`，不可配置）、commands/MCP 的同构双根与 `~/.agents/mcp.json` fallback、`~/.zcode/skills` 期望态为空、验证日期与本机证据。

### Stage 1：双区迁移与同步流改造

#### 6. `skills/` 顶层重构（git mv 批量，egm 试点先行三步走）

*   **Type / Scope**: 目录结构。
*   **Proposed Changes**: 按归因分类迁移，**内部显式分三步**（每步独立验收）——**第一步 egm 源试点**（shared_dirs 最复杂、`sync-skills.sh agents` 生成链依赖它，最早暴露全链路问题；验收 = egm 单源 pull 幂等 + `agents` 子命令链路正常）→ **第二步其余三源**（mattpocock/archify/sideshow，归因依据 `.skill-lock.json` v3 条目 + sources.conf 源内目录名比对）→ **第三步 own 三自研**（`code-walk`、`code-to-spec`、`architecture-diagram`）。**其余无源归因目录（25 个 addyosmani 命名 + diagram-design + 其他）暂留扁平区**，Stage 2 adopt-or-diff 归编。迁移用 `git mv` 保留历史。

#### 7. `hack/sync-skills.sh`（Modify，核心改造）

*   **Type / Scope**: 同步脚本三条流 + 新子命令。
*   **Proposed Changes**: (a) pull：目标改为 `skills/vendor/<source>/`，前置工作树干净 guard（脏则中止并提示先 commit），pull 后更新 lock v4 commit 锚，永不触碰 `own/`；(b) backup：只收 `own/` node 侧变更、`agents/`、`mcps/`、`harness/*/config/`；(c) restore：分区物化，deploy 端统一扁平 `~/.agents/skills/<install-name>/`；(d) 新增 `adopt` 子命令：adopt-or-diff 流程——对无源归因目录与上游 diff，干净则 `git mv` 归编 vendor 并记 lock，有差异则输出 diff 清单等作者裁决；(e) 跨源 install-name 撞名硬失败；(f) 脚本头写入数据流声明（git 为权威）。

#### 8. `.skill-lock.json`（Modify，v3 → v4）

*   **Type / Scope**: lock schema 迁移。
*   **Proposed Changes**: 按 Technical Plan 的 v4 schema 重写——每条目 `zone/source/commit/installName/pulledAt/orphaned`；vercel-labs/* 与 fireworks-tech-graph 历史条目标 `orphaned: true` 保留 provenance；`own/` 不入 lock。迁移与 Stage 1 目录重构同批提交。

#### 9. `README.md`（Modify）

*   **Type / Scope**: 仓库文档。
*   **Proposed Changes**: 更新目录布局图、数据流声明（pull/backup/restore 分区规则）、"repo 是唯一权威，node 是部署目标"的治理说明、doctor/setup 入口。

### Stage 2：per-harness 治理 + doctor + 新源

#### 10. `harness/{zcode,claude,antigravity,deepseek}/`（Create ×4）

*   **Type / Scope**: 治理目录（每 harness 三件套）。
*   **Proposed Changes**: 每目录：(a) `NOTES.md`——已验证机制说明（读哪里/怎么读/验证日期），zcode 用 Stage 0 结论，claude/antigravity/deepseek 由一次性会话验证补齐（claude skills 路径、antigravity mcp 文件名即 Q2'、deepseek mcp 在 `~/.dsh/` 体系内的真实位置），未验证项标 experimental；(b) `config/`——该 harness 配置文件备份（mcp 配置、settings 片段）；(c) `verify.sh`——fail-loudly 的部署验证（不静默跳过）。

#### 11. `hack/doctor.sh` + `hack/checks/c1..c8*.sh`（Create ×9）

*   **Type / Scope**: 期望态引擎 + 检查注册表。
*   **Proposed Changes**: doctor.sh 读期望态清单 + 遍历 `checks/*.sh`（元数据头声明 severity/auto-repairable），聚合输出（pass/warn/error/unverified 四态），`--fix` 只执行白名单修复，`--live` 叠加 C7；C1-C8 按 Technical Plan 表格实现，期望态清单初版 = 部署矩阵的机器可读化。

#### 12. `hack/setup.sh`（Create）

*   **Type / Scope**: 新机 bootstrap。
*   **Proposed Changes**: `--level N`（默认 3）：L0 结构+lock 校验 → L1 skills 物化 + C3/C4/C6 绿 → L2 agents 部署 → L3 MCP 配置写入（按 harness/*/NOTES.md 已验证路径）+ 服务存活 → L4 workflow 模板就位；每层结束跑 doctor 对应检查作验收门。

#### 13. `hack/sources.conf`（Modify）+ `hack/sync-skills.sh` adopt 执行

*   **Type / Scope**: 新源接入与归编。
*   **Proposed Changes**: sources.conf 追加 `git@github.com:addyosmani/agent-skills.git|skills|references` 与 `git@github.com:cathrynlavery/diagram-design.git|skills|`；执行 `adopt` 对 25 个 addyosmani 命名目录与 diagram-design 归编；pull 两新源；doctor 增加 addyosmani 共享树与上游漂移检查（附于 C5）。

#### 14. `hack/sync-mcps.sh`（Modify）

*   **Type / Scope**: MCP 配置路径修正。
*   **Proposed Changes**: 按 `harness/*/NOTES.md` 验证结论修正 deepseek（弃 `~/.deepseek/mcp.json`，改 `~/.dsh/` 体系内真实路径）与 antigravity（`mcp.json` vs `mcp_config.json`，Q2' 结论）写入路径；环境变量覆盖机制保留。

### Stage 3：workflow 模板通用化

#### 15. `docs/agents/feature-workflow.md`（Modify）

*   **Type / Scope**: 交付流程模板。
*   **Proposed Changes**: 项目特定内容（Go/GPFS/etcd/migrator 等示例）改占位符 `{{STACK}}`/`{{TEST_GATE}}` 等并附替换说明；头部加前置条件块（`/setup-matt-pocock-skills` 初始化声明）；技能引用改为槽位引用（查 `slot-map.md`）；在"阶段 1 设计提案"与"阶段 2 设计锁定"之间固定**方案设计阶段**（`egm-brainstorm → concepts_brief → egm-draft`）；"阶段 7 合并"后固定**偏差评审**（`egm-review` / `egm-drift-report`，对照 design 与实现）。

#### 16. `docs/agents/bugfix-workflow.md`（Modify）

*   **Type / Scope**: 缺陷流程模板。
*   **Proposed Changes**: 同上通用化（占位符 + 前置条件 + 槽位）；在"阶段 3 方案决策"处接 design 槽位（轻量：`egm-brainstorm` 可选、破坏性方案必经）；"阶段 6 合并关闭"前加偏差评审（轻量：`egm-review` 单轮）。

#### 17. `docs/agents/slot-map.md`（Create）

*   **Type / Scope**: 槽位映射表（两模板共享，单一事实源）。
*   **Proposed Changes**: 表：slot（grill/design/spec/tickets/implement/tdd/review/drift/diagnose）→ skill 名（grill-with-docs · egm-brainstorm+egm-draft · to-spec · to-tickets · implement · tdd · code-review · egm-review/egm-drift-report · diagnosing-bugs）→ 备注（可选/必选、轻量路径）；C8 检查消费本表。

### Verification Plan

*   **Stage 0**: `git status` 干净（archify 编辑已清）；新 ZCode 会话 skill 列表无重复；`~/.deepseek/agents/` 不存在；dsh 会话可见 code-walk。
*   **Stage 1**: 单源 pull 幂等重跑无 diff（`git status` 二次干净）；全量 restore 后 doctor static 全绿；lock v4 无未标注孤儿条目。
*   **Stage 2**: 临时 HOME 模拟新机（`HOME=$(mktemp -d)`），`hack/setup.sh` 到 L3 全过；doctor 零误报（dsh/zcode 零部署不报警）；`--live` 下 sideshow handshake 通过。
*   **Stage 3**: 两模板在无 Go/GPFS 上下文的新项目可直接套用（占位符替换说明自足）；C8 绿（slot-map 全部指向存在且已部署的 skill）。
*   **回归红线**: 每个 Stage 收尾跑一次全量 doctor static + `sync-mcps.sh status`，与上一 Stage 基线对比无新增 error。
