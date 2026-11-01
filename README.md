# respire

> 吸即存，呼即取——给 Kimi Code 装上本地加密记忆。

`respire` 是 Kimi Code 插件（清单 `kimi.plugin.json`，插件 id `respire`）：以 hooks 把 [respire（CLI 名 rsrs）](https://www.npmjs.com/package/@rsrsai/cli) 记忆引擎挂进 agent 循环——每轮标题档自动召回、「记：」一前缀即落库。本地优先、端侧加密、云端 LWW 同步；**不带自定义安装脚本，按 Kimi Code 标准 `/plugins` 链路安装**。

## 不装模型完全可用（降级是一等公民）

- **注册、登录、同步、召回全不依赖端侧模型**——装完插件即可用，未装模型时引擎自动走词面档（等同 memlite 未配嵌入的效果）。
- BGE-M3（量化版约 570MB）是**纯可选增强**：想要更好的语义召回再 `rsrs model install && rsrs model activate m3`，插件检测到未装会在会话内提示一句，装与不装都不报错、不拦路。

## 安装（Kimi Code 插件）

```bash
/plugins install https://github.com/risense-ai/respire-kimi
# 或本地路径：
/plugins install /本地路径/respire-kimi
```

装完 `/reload` 或 `/new` 开新会话即生效。**插件是用户级**（装入 `$KIMI_CODE_HOME/plugins/managed/respire/`），对你所有项目生效，不是单项目配置。

升级：`/plugins` 面板对 respire 执行更新（或重新 install 覆盖），随后 `/reload`。

引擎（rsrs CLI）缺失时插件会把安装命令交给 agent 代跑（`npm i -g @rsrsai/cli@latest`），可让 agent 代装，装完同会话内即恢复。

## 启用与关闭

| 档 | 怎么关 | 范围 |
| --- | --- | --- |
| 单轮 | prompt 前缀 `/nomem` | 只关本轮召回 |
| 总开关 | `hooks/respire.config.json` 设 `"enabled": false` | 记忆层全线静默（召回/落库/存储检查），hook.log 留 `disabled` 痕 |
| 插件级 | `/plugins disable respire` | Kimi 侧整插件卸力 |

## 装上后发生什么

| 时机 | 行为 |
| --- | --- |
| 会话全程 | `systemPromptPath`（SYSTEM.md）常驻系统提示：答前必查、收尾必存、遇障先翻忆、敏感红线五条简则 |
| `SessionStart`（startup/resume） | 加载 `skills/respire` playbook 技能进主 agent；同时做一次状态探测——引擎未装/未登录/库空/缺模型时的引导**写入 `.pending_nudge` 状态文件**（Kimi SessionStart 输出不进模型上下文），由首个 UserPromptSubmit 置顶带出后即删 |
| `UserPromptSubmit` | 自动 `rsrs recall --titles`：**标题档注入**——只给分数＋8 位短 id＋标题，正文由 agent `rsrs show <id>` 按需取；默认**直出不过滤**，噪音边界＝rsrs skip 门＋limit 5＋标题档；斜杠命令 token（`/skill:…`、`/respire:…`）自动剥除后再召回 |
| `prompt` 以「记：」「存：」「remember:」开头 | 直接 `rsrs remember … --importance important` 落库并回执，**回执按结果状态机**：`ok`/`warn` → **已写入**（warn 附引擎警告如 parent 未解析——不误报失败、不引导重发），随后 `show` 写后回读核验（verified / mismatch / unavailable 如实标注）；`pending` → **未写入**，转述候选（带短 id）＋引擎建议动作（改＞并＞挂＞存全量转达，先 `show` 读候选正文再决断）；超时/坏回执 → **结果未知**，回执只允许只读核实（`rsrs list`/`rsrs show`）并**明令禁止重发**（重复写风险）。回执硬约束 AI 抽「主语＋动作＋结果」事实句 `retitle` 替换暂拟题 |
| `Stop`（AI 干完活） | **存储检查**：以 `hookSpecificOutput.permissionDecision:"deny"` JSON 续跑一轮，提示模型把本轮新的**事实/决定/约定/教训/踩坑**分条 `rsrs remember`（事实句标题、判重先决断）；闲聊无新事实则直接结束。**每个真实请求至多催一次**：续跑轮 `stop_hook_active=true` 放行 ＋ 本层请求级一次收尾锁双保险（新 prompt 重新武装）。**免催凭证按请求判断**：同会话、本轮 prompt 之后的成功写回执（`ok`/`warn`+id）或引擎侧写入（`list` 最近 `updated_at` 晚于本轮 prompt）才免催——旧「近 10 分钟任意写入」跨轮误抑制已移除；缺凭证时宁可多一轮有界收尾。**查库失败/超时/坏信封一律 fail-open 放行**：记忆层故障不得拦主任务结束。节流 `store_nudge_every`（1=每轮，0=关，N=每 N 轮） |
| `prompt` 以 `/nomem` 开头 | 本轮跳过召回 |
| 快捷指令 | `/respire:recall <词>`、`/respire:store <内容>`、`/respire:sync`；技能本身经 `/skill:respire:respire` 唤起 |

## 首次使用 · 三件事

1. **注册登录**（开箱即用，不依赖模型）：[rsrs.rs](https://rsrs.rs) 注册 → 本机 `rsrs register`；日常 `rsrs login` 浏览器授权；autosync 常开，`rsrs sync` 手动同步，`rsrs status` 查态。
2. **导入既有记忆与规则（一次成库，LLM 代抽）**：开个新会话粘贴下面整段——

   > 请把本机 Kimi Code 的既有规则与记忆导入 respire：逐个读取——`~/.kimi-code/AGENTS.md`（用户级规则，若在）、你常用项目根下的 `AGENTS.md`、`~/.agents/skills/*/SKILL.md`；抽出可复用的事实、约定、教训与红线（口令、证件号、卡号、私钥一律排除、只记位置），去重后用 `rsrs remember` 分条存入（`--importance important`、标题按事实句；判重给候选先决断挂靠或合并），存完给我一份清单。

   空库首日 SessionStart 会注入同一线索（经首个 prompt 带出）。
3. **端侧模型（可选增强）**：`rsrs model install && rsrs model activate m3`——不装完全可用，想要更好语义召回再装。

## 调优（可选）

`$KIMI_CODE_HOME/plugins/managed/respire/hooks/respire.config.json`（缺失即全默认，改完 `/reload` 或新会话生效；**不涉及登录与账号**）：

| 字段 | 默认 | 含义 |
| --- | --- | --- |
| `rsrs` | `""` | 引擎路径；空 = 自动探测（配置 → `RESPITE_RSRS`/`RESPIRE_BIN` 环境变量 → PATH → `~/.local/bin` → `~/.rsrs/bin` → `~/.npm-global` → `/usr/local/bin` → `/usr/bin`） |
| `recall_threshold` | `0.0` | 召回下限；**0=默认关（rsrs 直出）**，设正数才启用过滤 |
| `recall_limit` | `5` | 取前 N 条 |
| `min_prompt_chars` | `2` | 1 字才跳，2 字起即查 |
| `session_rules` | `true` | SessionStart 是否做状态探测并写 `.pending_nudge` 引导（Kimi 下简则由 `systemPromptPath` 常驻承担，此开关只管探测引导） |
| `budget_chars` | `1500` | 单轮注入总预算（标题行远短于此） |
| `enabled` | `true` | **总开关**：false=全线静默 |
| `store_nudge_every` | `1` | Stop 存储检查节流：1=每轮、N=每 N 轮、0=关（每轮=多一轮模型小调用） |
| `log` | `true` | `hooks/hook.log` 留痕（超 256KB 清轮） |
| `skip_prefixes` | `[]` | 宿主内部提示白名单：命中这些前缀（大小写不敏感）的 prompt 不召回也不落库 |

过滤策略：**默认不设阈值**——三层已框住噪音：rsrs skip 门、limit 5、标题档。历史教训：阈值每降一次都是真相关被拦的补救，漏召代价远大于多看两行标题。

## 卸载

```text
/plugins remove respire
```

## 设计要点

- **fail-open**：hook 任何异常 → 空 stdout + `exit 0`，永不拦会话；失败必留痕于 hook.log（口令/token/长数字脱敏）
- **Kimi 适配点**（相对 dimcode/qoder/workbuddy  siblings）：
  - SessionStart 是观察型事件、**stdout 不进模型上下文**——Dim 系「SessionStart 注简则」方案在 Kimi 不可移植。替代：规则走 `systemPromptPath`（常驻系统提示）+ `sessionStart.skill`（每会话加载 playbook）；状态探测引导改**写 `.pending_nudge` 状态文件**，由首个 UserPromptSubmit 读出、删除并置顶带出
  - Stop 阻断用 Kimi 文档 JSON：`hookSpecificOutput.permissionDecision:"deny"` + `permissionDecisionReason` 打 stdout、exit 0（与 fail-open 同路，不用 exit 2）
  - hooks 直接内联在 `kimi.plugin.json`（hook cwd = 插件根，`./` 相对路径；无 hooks.json、无 statusMessage 字段）；事件名取 `KIMI_HOOK_EVENT` 环境变量，stdin `hook_event_name` 兜底
  - 斜杠命令（`/skill:respire:respire`、`/respire:recall` 等）token 在召回前剥除，防命令名词面污染 query
- **标题档注入**：`recall --titles` 只回 id/score/title，正文交 `show` 按需拉取；`superseded_by` 标「已被取代」
- **判后即存尊重设计**：落库不带 `--force`，`pending` 候选原样转述给模型决断
- **包内自检**：`python3 scripts/validate_plugin.py`（结构/清单/hooks 形状/可编译/fail-open/阻断 JSON/敏感扫描），分发前必跑

## 已知边界

- **真机安装加载未在本仓 CI 验证**：清单与 hooks 形状按官方文档（2026-10-23 核对）静态对齐，`/plugins install` 后的真实加载路径以你本机实测为准
- **召回质量是引擎上限**：用词鸿沟下 BGE-M3 可能漏召真条——简则已约束模型「命中不贴题换词补查」（同义词/上位词/英文词分路）
- **冷启动窗**：runtime 冷启＋模型加载实测 7s+，故 hook timeout 20s、recall 14s、probe 10s；探测失败时引导段落带冷启动诊断
- **SessionStart matcher 仅 `startup|resume`**：Kimi 不支持 clear/compact 匹配；长会话压缩后若简则丢失，`/reload` 或新会话即复
- **留痕**：`hooks/hook.log` 每事件一行（ts/ev/out/ms/d 含 query 摘要），按行复盘「灵不灵」

## 测试

```bash
python3 scripts/validate_plugin.py   # 包结构自检（Kimi 清单/hooks 形状/可编译/阻断 JSON/敏感扫描）
bash tests/test_hooks.sh             # 行为只读断言（探测/挂起引导带出/召回/剥前缀/清洗/节流），不碰库
bash tests/test_hooks.sh --store     # 加写探针（写真库→回执→rsrs forget 自清理）
```

rsrs 无 data-dir 隔离（runtime 单例＋全局 client.json），故写测试仅在显式开启时进行，即写即忘。

## License

MIT
# CI 与发布维护

GitHub Actions 在 Linux、Windows、macOS 上运行结构校验、临时桩行为及发布策略测试；不执行旧完整脚本中的真实引擎探测或数据库操作。测试要求普通输入正向调用、死桩负对照、凭据零调用、防重入和节流、挂起引导消费、版本一致性，以及从原脚本单独提取的 `probe_cleanup` 回执兼容检查。清理测试只调用临时记录桩的 `forget`，不会删除真实记录。

通过审核后的 `vMAJOR.MINOR.PATCH` 标签触发发布，ZIP 保留插件根目录布局并附带 SHA256SUMS。安装仍使用本文原有仓库安装说明。恢复已存在标签时，从 main 手动运行工作流并提供标签及其完整提交 SHA；只归档该提交，不移动标签，不覆盖冲突资产。构建默认只读，写权限仅在受控发布 job 内使用仓库 GITHUB_TOKEN，无新增 secret。

这些测试不能代替真实 Kimi 宿主、安装后的解释器回退或真实引擎验收；任何版本或回执兼容测试失败都阻止发布。
