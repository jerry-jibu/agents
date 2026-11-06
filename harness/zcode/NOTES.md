# ZCode — 已验证机制说明（NOTES）

* **验证日期**: 2026-11-06
* **验证方式**: 官方文档（zcode-guide:zcode-configuration-guide v0.3.0）+ 本机会话实测
* **状态**: skills 面已验证并落地；commands 面机制已知、会话级表现待一次验证

## Skills 发现机制（已验证）

ZCode 用户级 skills 发现根**固定**为两处，不可配置移除：

1. `~/.zcode/skills/`（先扫描）
2. `~/.agents/skills/`

同名 skill 在两处**都会被发现**；发现序内先到者遮蔽后者（`.zcode` 优先于 `.agents`）。
Workspace 级另扫 `<repo>/.zcode/skills` 与 `<repo>/.agents/skills`（从 cwd 向上到 repo 根，每级都算；越深优先级越高）。

**本机证据**：2026-11-06 会话中每个 skill 出现两次（`~/.zcode/skills/<n>` 与 `~/.agents/skills/<n>` 双路径）；实测 `~/.zcode/skills/` 全部 79 条均为指向 `../../.agents/skills/<name>` 的 symlink，无任何 zcode 独有内容（`find -maxdepth 1 -not -type l` 仅返回根目录）。

**处置（Stage 0 已执行）**：79 条 symlinks 全部删除，`~/.zcode/skills` 保持为空；`~/.agents/skills` 成为唯一用户级 skills 根（ZCode 与 dsh 原生双读同一根）。

**期望态（doctor C3 消费）**：`~/.zcode/skills` 不得含与 `~/.agents/skills` 同名的条目；默认应为空。

## Commands 发现机制（机制已知，会话级表现待验证）

与 skills 同构双根：`~/.zcode/commands/` 先于 `~/.agents/commands/`；dedupe 规则为"规范化命令名 first-match-wins，败者被忽略"（与 skills 的"全部发现、先到遮蔽"不同——commands 是忽略而非遮蔽）。

**待验证**：commands 双根在会话中的实际表现（重复 or 忽略）——一次新 ZCode 会话放置同名 command 验证；结论出来前 C3 不泛化到 commands 面。

## MCP 配置（已验证）

* 用户级：`~/.zcode/cli/config.json` → `mcp.servers`（本设计走 http entry：sideshow `localhost:8228/mcp`）
* Fallback：`~/.agents/mcp.json` → `mcpServers`
* User 同名 server 覆盖 workspace；workspace 级默认 trusted 并自动连接

## Subagents

`~/.zcode/agents/`（已验证 live：10 个 egm-*.md 由 `sync-skills.sh agents` 从 skill personas 生成）。
