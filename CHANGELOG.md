# Changelog

## 0.1.3 — 审计整改：写结果状态机＋Stop fail-open＋请求级免催凭证（KM-01~KM-05）

### Fixed

- **KM-01 Stop fail-open**：查库 `list` 失败/超时/坏信封时直接放行，不再 deny——记忆层故障不得强迫主任务续跑；无新内容也不因查库故障多一轮。
- **KM-02 未知写结果只读核实**：超时/坏回执/无输出归为 **unknown**——回执明令「`rsrs list`/`rsrs show` 只读核实、禁止重发 remember」（旧文案「手动 rsrs remember 核实」有重复写风险）；秒回坏回执自动 `list` 核对并报告可能已写。`warn`+有效 id 是**已写入带警告**，如实回执不误报失败。
- **KM-03 快存回执闭环**：ok/warn 后 `show` 写后回读核验（R11）；pending 保留候选短 id 与引擎建议动作全量（改＞并＞挂＞存，§7.2）。
- **KM-04 请求级免催凭证＋一次收尾锁**：废除「近 10 分钟任意写入」全局抑制（跨轮误抑制，含 hook.log 扫描路径）；`.store_turn` 同会话、本轮 prompt 之后的凭证才免催；宿主未带 `stop_hook_active` 时同一请求至多 deny 一次，新 prompt 重新武装。
- **KM-05 规范声明**：README 明确「主模型不再强制逐轮读完整 CLI 政策」是产品决策——规则文本不再要求 policy-read，完整政策由模型按需 `rsrs prompt` 获取；后台/显式写入路径仍遵守引擎判重。

### Changed

- 测试：CI 白名单升级为有序调用序列（remember→show），spy 支持 warn/pending/silent/hang/show_mismatch；新增 8 个契约测试并翻转 failed→deny 旧错误期望（33/33）。bash 套件：fresh 桩改动态毫秒时间戳、增 bad 桩（fail-open）、Stop 场景化复位、PR env 传 prompt（修 MSYS 路径转换）、heredoc 走 stdout.buffer（修 Windows 码页乱码）、title 路径 wpath 化（75/6 → 85/0，--store 89/0）。`RESPITE_TEST_FAST`/`RESPITE_TURN_STATE` 测试后门；`.gitignore` 增 `.store_turn`。

## 0.1.1 — 2026-10-31 · 提示词英文化（dimcode 同款）＋疑似凭据拦截
## 0.1.1 — 2026-10-31 · 提示词英文化（dimcode 同款）＋疑似凭据拦截

- 模型可见文本全量英文化：hook 注入段（NO_RSRS / LOGIN_NUDGE / EMPTY_NUDGE / NO_MODEL / PROBE_FAIL / STORE_NUDGE）、落库回执、召回头行、SYSTEM.md 常驻简则、commands（recall/store/sync）、SKILL.md 全部改英文（dimcode 0.5.6 同款）；「记：」等中文前缀兼容不变；SKILL.md 触发词保留中文。
- 新增输入侧疑似凭据扫描（`contains_secret`）：命中 prompt 不召回也不落库，注入 `SECRET_SKIP` 提示。
- 安装与注册口径对齐 CLI 现状：`rsrs-cli@latest`；本机 `rsrs register` 直注、无网站步骤（含插件清单 description / longDescription 修正）。
- 测试断言随英文输出同步，新增疑似凭据两条。

## 0.1.0 — 2026-10-23 · 初始 Kimi Code 移植

- 以 respire-dimcode hooks/respire.py 0.5.4 为功能基线（含 `engine_last_store()` 问库节流、`data_dir()` 链、`skip_prefixes` 白名单），注入/回执文案全中文（沿用 workbuddy 措辞，`EMPTY_NUDGE` 导入线索改指 `~/.kimi-code/AGENTS.md` 与 `~/.agents/skills/*/SKILL.md`）
- **Kimi 适配**：清单改 `kimi.plugin.json`（hooks 内联数组，每规则仅 event/matcher/command/timeout，无 hooks.json/statusMessage）；规则常驻改走 `systemPromptPath`（SYSTEM.md）+ `sessionStart.skill`；SessionStart 输出不进模型上下文 → 状态探测引导改写 `.pending_nudge` 状态文件（`RESPITE_PENDING_NUDGE` 可覆写），由首个 UserPromptSubmit 置顶带出即删；Stop 阻断改 `hookSpecificOutput.permissionDecision:"deny"` JSON（stdout + exit 0）；事件名取 `KIMI_HOOK_EVENT`（`DIM_HOOK_EVENT` 与 stdin `hook_event_name` 兜底）；`RULES` 简则常量在 Kimi 侧由 SYSTEM.md 取代，不再由 SessionStart 打印
- `on_prompt` 增斜杠命令剥除（`^/[^\s]+(\s+|$)`，`/skill:…`、`/respire:…` 不再污染召回 query；剥后无实义仅带出挂起引导）；`find_rsrs()` 探测链补 `RESPIRE_BIN`、`which("respire")`、`~/.npm-global/bin` 与去重
- 新增 `commands/`（recall/store/sync 三个中文斜杠指令）；新增 `scripts/validate_plugin.py`（Kimi 清单/hooks 形状/UTF-8/SKILL frontmatter/可编译/阻断 JSON/敏感扫描自检）；测试断言全面 Kimi 化（SessionStart 恒空、挂起引导带出即删、deny JSON、剥前缀召回）
