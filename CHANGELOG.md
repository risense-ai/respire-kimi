# Changelog

## 0.1.6 — 2026-11-01

- Bound CLI timeout cleanup across wrapper/child trees (Windows taskkill on the owned PID; POSIX process group). Verify descendants cannot keep response pipes open after the deadline.

- Reject invalid write IDs and mismatched/non-string read-back fields; preserve committed receipts without retries.
- Filter internal prompts before rearming; Stop uses only its one-shot latch, never stale write snapshots. Clamp remember/read-back/verification to one monotonic budget.


## 0.1.5 — 2026-11-01 · 复审第三轮（P2）：id 白名单严格化

### Fixed

- **畸形/非字符串 id 不再被当有效写入凭证（复审第三轮 P2）**：旧校验先把 `summary.id` 强转 `str` 再匹配宽松字符类 `[0-9a-fA-F][0-9a-fA-F-]{7,}`，导致 JSON 数字 `12345678`、`"a-------"`、`"abcdef01-0000-4"` 等非法值也能进入 ok/warn 的 Saved 分支并 `mark_store`（即使回读不可用仍保留 Saved、可令 Stop 免催）。改为**严格类型＋白名单**（zcode/dimcode 终案同款）：id 必须为原生字符串（数字不 `str()` 强转），且 `re.fullmatch` 完整 UUID（8-4-4-4-12）或 16+ 位纯 hex——不匹配一律 `sid=""` 归 **unknown**（只读核实、禁重发、不 mark_store），与缺 id/坏 summary 同路径。

### Changed

- 测试：CI 40/40（+复审三类反例 `ok_numid`/`ok_dashid`/`ok_shortgrp` 的 ok/warn 双状态完整 hook 测试：断言 unknown 回执＋Do NOT resend＋不含 Saved＋调用序列仅 remember→list（无写后回读 show）＋随后 Stop 仍催存（mark_store 未登记）；正向确认补完整 UUID 与 32 位 hex 两档合法 id 仍 Saved＋回读 verified＋Stop 免催）。README「记：」行同步 id 白名单口径。

## 0.1.4 — 2026-11-01 · 维护者复审整改（5 项＋回读附注）

### Fixed

- **KM-06 每会话原子一次收尾锁（复审#1）**：`.store_turn` 单文件共享状态改为**每会话独立锁文件**（`O_CREAT|O_EXCL` 原子独占——并发/交错会话 Stop 只有一个能落锁，A→B→A 不丢锁、不覆盖他人凭证）；无法落锁（状态目录不可写、被同名文件挡住等）一律放行——**绝不无锁 block**，状态写入失败不假装保险已生效；prompt_ts/store_ts 移入尽力维护的 per-session map（temp+rename 原子替换，仅按数量收敛、不按时间失效），map 失败只损失免催优化，不影响一次上限保证。
- **KM-07 锁不设 TTL（复审#2）**：600 秒过期使「每请求至多一次」失效——锁一经占用只有新真实 prompt（`mark_prompt`）删除重新武装；601 秒后、重复 Stop、交错会话均不再 deny；`/nomem` 仍算新请求（mark 提前到 /nomem 判断之前），只跳召回不跳重武装。
- **KM-08 回执/回读加固（复审#3＋附注）**：`ok`/`warn` 缺有效 id（hex/uuid 白名单校验）、畸形 summary（类型防护不抛异常）、未知 status 一律归 **unknown**（只读核实＋禁重发，不当失败也不当成功）；`skip`=引擎按当前模式拒绝（未写非失败），仅 `fail` 断言未接受。回读改**全量核验**：返回 id 必须=写入 id、标题相等、完整正文相等才称 verified；错误 id/同前缀不同尾部 → mismatch 如实标注。
- **KM-09 共享 hook 预算（复审#4）**：remember/回读/只读核实共用一条截止时间（`RESPITE_HOOK_BUDGET_S`，默认 20s，预留 2.5s 输出余量）——慢坏回执后剩余不足直接 unknown，不再无预算判断地追加 list（旧 18s+6s 可超 20s hook 上限，unknown/禁重发提示可能来不及输出）。
- **KM-10 免催只认可归属凭证（复审#5）**：移除「引擎全库最新写入晚于本轮 prompt 即免催」（无法归属会话/请求——其他会话并行写入会误抑制本会话）；`Stop` **完全不查询引擎**（删 `engine_last_store` 全库时间免催链路），也因此不存在查库失败强迫续跑/放行的路径。

### Changed

- 测试：CI 38/38（+复审反例：缺 id/垃圾 id/坏 summary→unknown、skip 回执、错 id/尾部篡改回读→mismatch、慢坏回执+紧预算→零追加调用、坏 schema list 不归属、A→B→A 锁不丢、锁无 TTL、状态不可写放行、Stop 零引擎查询）；bash 89/0（fresh 场景翻转为仍催；新增不可写目录放行、25 小时锁仍占用、/nomem 重武装、单次 nudge 计数；留痕 grep 改 `once_latch_skip`）。`.gitignore` 增 `.latch_*`/`turn_map.json`（运行期锁/凭证文件不进仓）。

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

- 模型可见文本全量英文化：hook 注入段（NO_RSRS / LOGIN_NUDGE / EMPTY_NUDGE / NO_MODEL / PROBE_FAIL / STORE_NUDGE）、落库回执、召回头行、SYSTEM.md 常驻简则、commands（recall/store/sync）、SKILL.md 全部改英文（dimcode 0.5.6 同款）；「记：」等中文前缀兼容不变；SKILL.md 触发词保留中文。
- 新增输入侧疑似凭据扫描（`contains_secret`）：命中 prompt 不召回也不落库，注入 `SECRET_SKIP` 提示。
- 安装与注册口径对齐 CLI 现状：`rsrs-cli@latest`；本机 `rsrs register` 直注、无网站步骤（含插件清单 description / longDescription 修正）。
- 测试断言随英文输出同步，新增疑似凭据两条。

## 0.1.0 — 2026-10-23 · 初始 Kimi Code 移植

- 以 respire-dimcode hooks/respire.py 0.5.4 为功能基线（含 `engine_last_store()` 问库节流、`data_dir()` 链、`skip_prefixes` 白名单），注入/回执文案全中文（沿用 workbuddy 措辞，`EMPTY_NUDGE` 导入线索改指 `~/.kimi-code/AGENTS.md` 与 `~/.agents/skills/*/SKILL.md`）
- **Kimi 适配**：清单改 `kimi.plugin.json`（hooks 内联数组，每规则仅 event/matcher/command/timeout，无 hooks.json/statusMessage）；规则常驻改走 `systemPromptPath`（SYSTEM.md）+ `sessionStart.skill`；SessionStart 输出不进模型上下文 → 状态探测引导改写 `.pending_nudge` 状态文件（`RESPITE_PENDING_NUDGE` 可覆写），由首个 UserPromptSubmit 置顶带出即删；Stop 阻断改 `hookSpecificOutput.permissionDecision:"deny"` JSON（stdout + exit 0）；事件名取 `KIMI_HOOK_EVENT`（`DIM_HOOK_EVENT` 与 stdin `hook_event_name` 兜底）；`RULES` 简则常量在 Kimi 侧由 SYSTEM.md 取代，不再由 SessionStart 打印
- `on_prompt` 增斜杠命令剥除（`^/[^\s]+(\s+|$)`，`/skill:…`、`/respire:…` 不再污染召回 query；剥后无实义仅带出挂起引导）；`find_rsrs()` 探测链补 `RESPIRE_BIN`、`which("respire")`、`~/.npm-global/bin` 与去重
- 新增 `commands/`（recall/store/sync 三个中文斜杠指令）；新增 `scripts/validate_plugin.py`（Kimi 清单/hooks 形状/UTF-8/SKILL frontmatter/可编译/阻断 JSON/敏感扫描自检）；测试断言全面 Kimi 化（SessionStart 恒空、挂起引导带出即删、deny JSON、剥前缀召回）
