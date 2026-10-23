# Changelog

## 0.1.0 — 2026-10-23 · 初始 Kimi Code 移植

- 以 respire-dimcode hooks/respire.py 0.5.4 为功能基线（含 `engine_last_store()` 问库节流、`data_dir()` 链、`skip_prefixes` 白名单），注入/回执文案全中文（沿用 workbuddy 措辞，`EMPTY_NUDGE` 导入线索改指 `~/.kimi-code/AGENTS.md` 与 `~/.agents/skills/*/SKILL.md`）
- **Kimi 适配**：清单改 `kimi.plugin.json`（hooks 内联数组，每规则仅 event/matcher/command/timeout，无 hooks.json/statusMessage）；规则常驻改走 `systemPromptPath`（SYSTEM.md）+ `sessionStart.skill`；SessionStart 输出不进模型上下文 → 状态探测引导改写 `.pending_nudge` 状态文件（`RESPITE_PENDING_NUDGE` 可覆写），由首个 UserPromptSubmit 置顶带出即删；Stop 阻断改 `hookSpecificOutput.permissionDecision:"deny"` JSON（stdout + exit 0）；事件名取 `KIMI_HOOK_EVENT`（`DIM_HOOK_EVENT` 与 stdin `hook_event_name` 兜底）；`RULES` 简则常量在 Kimi 侧由 SYSTEM.md 取代，不再由 SessionStart 打印
- `on_prompt` 增斜杠命令剥除（`^/[^\s]+(\s+|$)`，`/skill:…`、`/respire:…` 不再污染召回 query；剥后无实义仅带出挂起引导）；`find_rsrs()` 探测链补 `RESPIRE_BIN`、`which("respire")`、`~/.npm-global/bin` 与去重
- 新增 `commands/`（recall/store/sync 三个中文斜杠指令）；新增 `scripts/validate_plugin.py`（Kimi 清单/hooks 形状/UTF-8/SKILL frontmatter/可编译/阻断 JSON/敏感扫描自检）；测试断言全面 Kimi 化（SessionStart 恒空、挂起引导带出即删、deny JSON、剥前缀召回）
