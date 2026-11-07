# Antigravity — 机制说明（NOTES）

* **验证日期**: 2026-11-07（目录级证据已验证；mcp 文件名 Q2' 与 skills 路径待会话验证）
* **状态**: home 归属已验证；mcp 文件名二选一待定；skills 读取路径待验证

## Home 归属（已验证，2026-11-06）

`~/.gemini/` 是 Antigravity 真实 home——app 自建状态目录：`antigravity/`
（conversations/brain/presence 等 protobuf）、`jetski-standalone-oauth-token`、
`config/`（含 `.migrated` 标记、`agents/`、`projects/`、`sidecars/`），另有
`~/Library/Application Support/Antigravity`。

## Agents（已验证）

`~/.gemini/config/agents/` — 10 个 persona（array 格式 tools）。2026-11-07
实测与 repo `agents/` 一致。

## MCP（Q2' 唯一遗留：文件名二选一）

`config/` 下并存两个候选（同日创建）：
* `mcp.json` — 150B，含 sideshow stdio entry（我们的写入）
* `mcp_config.json` — 0 字节

**验证方法（Q2'）**：开一个 Antigravity 会话，看 sideshow 工具是否出现；
未出现则把配置写入 `mcp_config.json` 复测。结论回填本文件与 expected.json。

## Skills（experimental，待验证）

是否原生读取 `~/.agents/skills`（参照 zcode/dsh）或有独立路径——待会话验证。
验证前列入 expected.json 的 unverified，doctor 输出 unverified 不计退出码。
