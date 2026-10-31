#!/usr/bin/env bash
# respire 自测（Kimi Code 版）—— 模拟 stdin 事件 JSON，逐分支断言。
# rsrs 无 data-dir 隔离（runtime 单例＋全局 client.json），故默认只读分支不碰库；
# 加 --store 才跑写探针（写真库→回执断言→rsrs forget 自清理）。
# Kimi 适配：SessionStart stdout 恒为空（观察型事件，输出不进模型上下文），
# 引导断言一律走 .pending_nudge 状态文件（RESPITE_PENDING_NUDGE 覆写路径，首条 prompt 带出即删）。
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY3="$(command -v python3)"
RSRS="$(command -v rsrs || true)"
[ -z "$RSRS" ] && RSRS="$HOME/.local/bin/rsrs"
[ -z "$RSRS" ] && RSRS="$HOME/.rsrs/bin/rsrs"
PASS=0; FAIL=0
WITH_STORE=0
[ "${1:-}" = "--store" ] && WITH_STORE=1

if [ -z "$RSRS" ] || [ ! -x "$RSRS" ]; then
  echo "SKIP：未找到 rsrs（respire 引擎），无法自测。"; exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/data"
CFG_ON="$TMP/config-on.json"
echo '{"session_rules": true}' > "$CFG_ON"
CFG_OFF="$TMP/config-off.json"
echo '{"session_rules": false}' > "$CFG_OFF"

# run <event> [prompt] [config] —— 每次调用独立 pending 路径，杜绝测试间挂起引导互染
run() {
  local ev="$1" pr="${2-}" cfg="${3:-$CFG_ON}" pend="$TMP/pending_$RANDOM$RANDOM$RANDOM"
  "$PY3" - "$ev" "$pr" <<'PY' | RESPITE_CONFIG="$cfg" RESPITE_LOG="$TMP/hook.log" RESPITE_NUDGE_STATE="$TMP/nudge" RESPITE_DATA="$TMP/data" RESPITE_PENDING_NUDGE="$pend" "$PY3" "$ROOT/hooks/respire.py" "$ev"
import json, sys
ev, pr = sys.argv[1], sys.argv[2]
d = {"hook_event_name": ev, "cwd": "/tmp", "session_id": "selftest"}
if ev == "UserPromptSubmit":
    d["prompt"] = pr
sys.stdout.write(json.dumps(d, ensure_ascii=False))
PY
}

# ss_fixed <pend路径> [config]：固定 pending 路径跑 SessionStart（调用处以环境变量前缀注入 FAKE 后门）
ss_fixed() {
  local pend="$1" cfg="${2:-$CFG_ON}"
  RESPITE_CONFIG="$cfg" RESPITE_LOG="$TMP/hook.log" RESPITE_NUDGE_STATE="$TMP/nudge" RESPITE_DATA="$TMP/data" RESPITE_PENDING_NUDGE="$pend" "$PY3" "$ROOT/hooks/respire.py" SessionStart <<'JSON'
{"hook_event_name":"SessionStart","session_id":"selftest","cwd":"/tmp"}
JSON
}

# ps_fixed <pend路径> <prompt> [config]：固定 pending 路径跑 UserPromptSubmit
ps_fixed() {
  local pend="$1" pr="$2" cfg="${3:-$CFG_ON}"
  PR="$pr" "$PY3" - <<'PY' | RESPITE_CONFIG="$cfg" RESPITE_LOG="$TMP/hook.log" RESPITE_NUDGE_STATE="$TMP/nudge" RESPITE_DATA="$TMP/data" RESPITE_PENDING_NUDGE="$pend" "$PY3" "$ROOT/hooks/respire.py" UserPromptSubmit
import json, os, sys
sys.stdout.write(json.dumps({"hook_event_name": "UserPromptSubmit", "session_id": "selftest",
                             "prompt": os.environ["PR"]}, ensure_ascii=False))
PY
}

check() {   # check <名字> <实际输出> <模式: 非空|空|含:xxx|不含:xxx>
  local name="$1" got="$2" want="$3" ok=0
  case "$want" in
    非空) [ -n "$got" ] && ok=1 ;;
    空)   [ -z "$got" ] && ok=1 ;;
    不含:*) printf '%s' "$got" | grep -qF -e "${want#不含:}" && ok=0 || ok=1 ;;
    含:*) printf '%s' "$got" | grep -qF -e "${want#含:}" && ok=1 ;;
  esac
  if [ "$ok" = 1 ]; then
    PASS=$((PASS+1)); echo "PASS  $name"
  else
    FAIL=$((FAIL+1)); echo "FAIL  $name  期望[$want] 实际[$(printf '%s' "$got" | head -c 200)]"
  fi
}

# Stop 节流分支的引擎桩：只回 list --json，fresh=刚落库 / stale=陈旧（真机库随时有人写，不能拿真引擎断言催/不催）
STUB_FRESH="$TMP/rsrs-fresh"; STUB_STALE="$TMP/rsrs-stale"
FRESH_TS="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
cat > "$STUB_FRESH" <<EOF
#!/usr/bin/env bash
[ "\${1:-}" = list ] && printf '{"command":"list","status":"ok","details":[{"id":"aaaaaaaaaaaaaaaa","created_at":"$FRESH_TS","updated_at":"$FRESH_TS","title":"fresh","content":"x"}]}'
exit 0
EOF
cat > "$STUB_STALE" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = list ] && printf '{"command":"list","status":"ok","details":[{"id":"bbbbbbbbbbbbbbbb","created_at":"2020-01-01T00:00:00.000Z","updated_at":"2020-01-01T00:00:00.000Z","title":"stale","content":"x"}]}'
exit 0
EOF
chmod +x "$STUB_FRESH" "$STUB_STALE"
CFG_STALE="$TMP/config-stale.json"
echo '{"session_rules": true, "rsrs": "'"$STUB_STALE"'"}' > "$CFG_STALE"
CFG_FRESH="$TMP/config-fresh.json"
echo '{"session_rules": true, "rsrs": "'"$STUB_FRESH"'"}' > "$CFG_FRESH"

# ---- SessionStart（Kimi：stdout 恒为空；引导走 .pending_nudge） ----
check "SessionStart 标准输出恒为空(常态)" "$(run SessionStart)" "空"
check "SessionStart 标准输出恒为空(再次)" "$(run SessionStart)" "空"
check "README 载三件事(模型可选)" "$(cat "$ROOT/README.md")" "含:不装模型完全可用"
check "README 载标准装法" "$(cat "$ROOT/README.md")" "含:/plugins install"
check "包内无自定义安装脚本" "$( { [ -e "$ROOT/install.sh" ] || [ -e "$ROOT/uninstall.sh" ]; } && echo PRESENT || echo absent )" "含:absent"
check "示例配置含 skip_prefixes 字段" "$(grep -q 'skip_prefixes' "$ROOT/hooks/respire.config.example.json" && echo YES)" "含:YES"
check "SYSTEM 简则载答前必查" "$(cat "$ROOT/SYSTEM.md")" "含:Recall before answering"
check "SYSTEM 简则载记前缀与nomem" "$(cat "$ROOT/SYSTEM.md")" "含:/nomem"

# 未登录引导：写挂起文件而非 stdout，首条 prompt 带出后删除
PEND="$TMP/pending_login"; rm -f "$PEND"
check "SessionStart 未登录仍静默" "$(RESPITE_FAKE_LOGGED_OUT=1 ss_fixed "$PEND")" "空"
check "未登录写挂起引导文件" "$( [ -s "$PEND" ] && echo YES || echo NO )" "含:YES"
check "挂起引导含登录文案" "$(cat "$PEND" 2>/dev/null)" "含:not signed in"
check "登录引导给出注册与代登法" "$(cat "$PEND" 2>/dev/null)" "含:rsrs login --oauth --no-open"
PEND_OUT="$(ps_fixed "$PEND" "rsrs 信封 JSON 结构解析取哪层")"
check "首条 prompt 带出挂起引导" "$PEND_OUT" "含:not signed in"
check "带出引导同时仍召回" "$PEND_OUT" "含:auto-recall"
check "引导带出后文件已删" "$( [ -e "$PEND" ] && echo PRESENT || echo gone )" "含:gone"

# 裸斜杠命令轮：剥后无实义 → 带出引导、不召回、不崩溃
PEND2="$TMP/pending_login2"; rm -f "$PEND2"
RESPITE_FAKE_LOGGED_OUT=1 ss_fixed "$PEND2" >/dev/null
SL_OUT="$(ps_fixed "$PEND2" "/skill:respire:respire")"
check "裸斜杠命令轮带出引导" "$SL_OUT" "含:not signed in"
check "裸斜杠命令轮不召回" "$SL_OUT" "不含:auto-recall"
check "裸斜杠命令轮引导文件已删" "$( [ -e "$PEND2" ] && echo PRESENT || echo gone )" "含:gone"

# 引擎缺失分支：monkeypatch find_rsrs→None（真机造不出「全路径皆缺」，走单元注入）
run_engineless() {   # run_engineless <event> [prompt]
  ROOT="$ROOT" TMP="$TMP" EV="$1" PR="${2-}" "$PY3" - <<'PY'
import io, json, os, sys, importlib.util
spec = importlib.util.spec_from_file_location("respire", os.path.join(os.environ["ROOT"], "hooks/respire.py"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.find_rsrs = lambda cfg: None
tmp = os.environ["TMP"]
for k, v in (("RESPITE_DATA", tmp + "/data"), ("RESPITE_LOG", tmp + "/hook.log"),
             ("RESPITE_NUDGE_STATE", tmp + "/nudge"), ("RESPITE_CONFIG", tmp + "/config-on.json"),
             ("RESPITE_PENDING_NUDGE", tmp + "/pending_eng_" + os.environ["EV"])):
    os.environ[k] = v
d = {"hook_event_name": os.environ["EV"], "session_id": "selftest", "cwd": "/tmp"}
if os.environ["EV"] == "UserPromptSubmit":
    d["prompt"] = os.environ["PR"]
sys.argv = ["respire.py", os.environ["EV"]]
sys.stdin = io.StringIO(json.dumps(d, ensure_ascii=False))
try:
    m.main()
except SystemExit:
    pass
PY
}
check "引擎缺失 SessionStart 静默" "$(run_engineless SessionStart)" "空"
check "引擎缺失装法落挂起文件" "$(cat "$TMP/pending_eng_SessionStart" 2>/dev/null)" "含:npm i -g rsrs-cli"
check "引导禁自造超级密码" "$(cat "$TMP/pending_eng_SessionStart" 2>/dev/null)" "含:never pass --super"
check "引导要求保存恢复码" "$(cat "$TMP/pending_eng_SessionStart" 2>/dev/null)" "含:copy and keep it"
check "引导含注册下一步" "$(cat "$TMP/pending_eng_SessionStart" 2>/dev/null)" "含:rsrs register with the user"
check "引擎缺失落库回装法" "$(run_engineless UserPromptSubmit "记：引擎缺失时的落库")" "含:npm i -g rsrs-cli"

# 缺模型 / 空库 / 探测失败：引导段落全部落挂起文件
PEND_M="$TMP/pending_model"; rm -f "$PEND_M"
RESPITE_FAKE_NO_MODEL=1 ss_fixed "$PEND_M" >/dev/null
check "缺模型写挂起装法" "$(cat "$PEND_M" 2>/dev/null)" "含:rsrs model activate m3"
check "缺模型点明词面档" "$(cat "$PEND_M" 2>/dev/null)" "含:lexical tier"
PEND_E="$TMP/pending_empty"; rm -f "$PEND_E"
RESPITE_FAKE_EMPTY=1 ss_fixed "$PEND_E" >/dev/null
check "空库写挂起引导" "$(cat "$PEND_E" 2>/dev/null)" "含:memory store is empty"
check "空库引导含 Kimi 导入线索" "$(cat "$PEND_E" 2>/dev/null)" "含:~/.kimi-code/AGENTS.md"
check "空库引导含技能导入线索" "$(cat "$PEND_E" 2>/dev/null)" "含:~/.agents/skills/*/SKILL.md"
PEND_F="$TMP/pending_probe"; rm -f "$PEND_F"
RESPITE_FAKE_PROBE_FAIL=1 ss_fixed "$PEND_F" >/dev/null
check "探测失败写挂起诊断段" "$(cat "$PEND_F" 2>/dev/null)" "含:status probe failed"
check "probe失败含未注册分支" "$(cat "$PEND_F" 2>/dev/null)" "含:never registered"
PEND_R="$TMP/pending_rules"; rm -f "$PEND_R"
RESPITE_FAKE_LOGGED_OUT=1 ss_fixed "$PEND_R" "$CFG_OFF" >/dev/null
check "session_rules=false 不写挂起引导" "$( [ -e "$PEND_R" ] && echo PRESENT || echo absent )" "含:absent"
check "session_rules=false 静默" "$(run SessionStart "" "$CFG_OFF")" "空"

# 日志留痕：任一事件后 hook.log 应有本行；口令脱敏
run SessionStart >/dev/null
run UserPromptSubmit "我的密码是 password: hunter2 这算敏感吗" >/dev/null
check "日志脱敏口令" "$(grep -q 'hunter2' "$TMP/hook.log" && echo LEAK || echo SAFE)" "含:SAFE"
check "日志脱敏留痕" "$(grep -q 'REDACTED' "$TMP/hook.log" && echo YES)" "含:YES"
check "hook.log 留痕" "$(grep -q '"ev": "session"' "$TMP/hook.log" 2>/dev/null && echo YES)" "含:YES"

# Stop 存储检查：<stop_hook_active>（节流断言一律走 stale 引擎桩，保证「仍催」确定性）
run_stop() {
  "$PY3" - "$1" <<'PY' | RESPITE_CONFIG="$CFG_STALE" RESPITE_LOG="$TMP/hook.log" RESPITE_NUDGE_STATE="$TMP/nudge" RESPITE_DATA="$TMP/data" RESPITE_PENDING_NUDGE="$TMP/pending_stop_$RANDOM$RANDOM" "$PY3" "$ROOT/hooks/respire.py" Stop
import json, sys
print(json.dumps({"hook_event_name": "Stop", "stop_hook_active": sys.argv[1] == "true"}))
PY
}
check "Stop 存储检查续跑(deny)" "$(run_stop false)" '含:"permissionDecision": "deny"'
check "Stop 含阻断原因字段" "$(run_stop false)" "含:permissionDecisionReason"
check "Stop 提示含存储指令" "$(run_stop false)" "含:rsrs remember"
check "Stop 防重入放行" "$(run_stop true)" "空"
CFG_NUDGE0="$TMP/config-nudge0.json"
echo '{"store_nudge_every": 0}' > "$CFG_NUDGE0"
run_stop_cfg() {   # $1=config
  local cfg="$1"
  "$PY3" - <<'PY' | RESPITE_CONFIG="$cfg" RESPITE_LOG="$TMP/hook.log" RESPITE_NUDGE_STATE="$TMP/nudge" RESPITE_DATA="$TMP/data" RESPITE_PENDING_NUDGE="$TMP/pending_stopcfg_$RANDOM$RANDOM" "$PY3" "$ROOT/hooks/respire.py" Stop
import json
print(json.dumps({"hook_event_name": "Stop", "stop_hook_active": False}))
PY
}
check "Stop 节流关闭静默" "$(run_stop_cfg "$CFG_NUDGE0")" "空"
check "Stop 引擎近期落库不催" "$(run_stop_cfg "$CFG_FRESH")" "空"
check "Stop 引擎陈旧落库仍催" "$(run_stop false)" '含:"permissionDecision": "deny"'
check "引擎放行留痕 src=engine" "$(grep -q 'stored_recent_skip.*src=engine' "$TMP/hook.log" && echo YES)" "含:YES"
printf '%s\n' '{"ts": "'"$(date +%Y-%m-%dT%H:%M:%S)"'", "ev": "store", "out": "ok", "d": "feed"}' >> "$TMP/hook.log"
check "Stop 已存放行放行" "$(run_stop false)" "空"
CFG_OFFE="$TMP/config-disabled.json"
echo '{"enabled": false}' > "$CFG_OFFE"
check "enabled=false 全线静默" "$(run SessionStart "" "$CFG_OFFE")" "空"
check "enabled=false 落库也静默" "$(run UserPromptSubmit "记：关断时不应落库" "$CFG_OFFE")" "空"

out=$(run UserPromptSubmit "rsrs 信封 JSON 结构解析取哪层")
check "相关 prompt 触发召回" "$out" "非空"
check "注入为标题档无正文" "$out" "不含:｜"
check "默认直出无阈值拦截" "$out" "含:rsrs direct"
check "召回头行与条数一致" "$(printf '%s' "$out" | python3 -c '
import re,sys
s=sys.stdin.read(); head=s.split("\n",1)[0]
n=sum(1 for l in s.split("\n") if l.startswith("- ["))
m=re.search(r"matched (\d+) item",head)
print("OK" if m and int(m.group(1))==n else "BAD")')" "含:OK"

CFG_BUDGET="$TMP/config-budget.json"
echo '{"budget_chars": 60}' > "$CFG_BUDGET"
check "预算砍行生效(至多1行)" "$(run UserPromptSubmit "rsrs 信封 JSON 结构解析取哪层" "$CFG_BUDGET" | python3 -c '
import sys
s=sys.stdin.read()
print(sum(1 for l in s.split("\n") if l.startswith("- [")))')" "含:1"

check "无关 prompt 不注入" "$(run UserPromptSubmit "今晚吃什么菜好呢")" "空"
check "单字 prompt 跳过" "$(run UserPromptSubmit "嗯")" "空"
check "/nomem 关闭召回" "$(run UserPromptSubmit "/nomem rsrs 信封结构")" "空"
check "疑似凭据不发引擎" "$(run UserPromptSubmit "api_key = sk-abcdefghijklmnopqrst 存一下")" "含:contains a credential"
check "疑似凭据不落库" "$(run UserPromptSubmit "记：数据库密码 = hunter2u")" "含:contains a credential"
check "斜杠命令剥前缀仍召回" "$(run UserPromptSubmit "/respire:recall rsrs 信封 JSON 结构解析取哪层")" "含:auto-recall"
check "斜杠命令整轮不召回不崩溃" "$(run UserPromptSubmit "/respire:recall")" "空"
check "裸斜杠不崩溃" "$(run UserPromptSubmit "/")" "空"
CFG_SKIP="$TMP/config-skip.json"
echo '{"skip_prefixes": ["recap:", "Weekly recap"]}' > "$CFG_SKIP"
check "skip_prefixes 命中不召回" "$(run UserPromptSubmit "Recap: 本周完成了 respire 插件移植总结" "$CFG_SKIP")" "空"
check "坏 stdin 静默" "$(printf 'not-json{{{' | RESPITE_CONFIG="$CFG_ON" RESPITE_LOG="$TMP/hook.log" RESPITE_DATA="$TMP/data" RESPITE_PENDING_NUDGE="$TMP/pending_bad_$RANDOM" "$PY3" "$ROOT/hooks/respire.py" UserPromptSubmit)" "空"
check "未知事件静默" "$(run PreToolUse "rsrs 信封")" "空"

# ---- title 规则抽取（纯函数，零污染） ----
check "整句优先取完整句" "$(python3 -c '
import sys,importlib.util
spec=importlib.util.spec_from_file_location("r","'"$ROOT"'/hooks/respire.py"); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.extract_title("memlite 插件路径迁至 memocap 下。后续以仓库为准。"))')" "含:memlite 插件路径迁至 memocap 下。"
check "无句号退分隔符不切半词" "$(python3 -c '
import sys,importlib.util
spec=importlib.util.spec_from_file_location("r","'"$ROOT"'/hooks/respire.py"); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
t=m.extract_title("这是一条没有句号的长事实句，讲清楚何时谁做了什么事，以及结果如何，后面还有别的内容")
print(t)')" "含:讲清楚何时谁做了什么事，"
check "长串不超70字" "$(python3 -c '
import sys,importlib.util
spec=importlib.util.spec_from_file_location("r","'"$ROOT"'/hooks/respire.py"); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(len(m.extract_title("默" * 200)))')" "非空"

# ---- 写探针（--store 显式开启；写真库→断言→forget 清理） ----
if [ "$WITH_STORE" = 1 ]; then
  # 内容须与全库零语义关联：纯随机无义串（域词如「探针/测试/记忆」会撞 30%+ 相似走待决态）
  MARK="zq$(date +%s)$RANDOM kw7f2 随机标记无义串"
  out=$(run UserPromptSubmit "记：$MARK")
  check "落库成功回执" "$out" "含:Saved:"
  check "回执约束AI抽事实句retitle" "$out" "含:rsrs retitle"
  SID=$(printf '%s' "$out" | sed -n 's/.*(\([0-9a-f]\{8\}\)).*/\1/p')
  check "回执带短 id" "$SID" "非空"
  if [ -n "$SID" ]; then
    rc=$(rsrs forget "$SID" --json 2>/dev/null | jq -r '.status // "err"')
    check "探针清理(status=ok)" "$rc" "含:ok"
  fi
  # 判重待决：复述库中稳定条目（1memory 更名 respire）→ 必撞高相似 → pending 未写入
  out=$(run UserPromptSubmit "记：1memory 更名 respire：吸即存呼即取，材料全线改（复述既有条目触发判重待决）")
  check "判重待决转述候选" "$out" "含:store pending"
  check "待决列出候选与决断法" "$out" "含:--force"
  # 兜底：万一判为直写（库条变更），清掉探针不留垃圾
  if printf '%s' "$out" | grep -qF "已存入"; then
    BID=$(printf '%s' "$out" | sed -n 's/.*(\([0-9a-f]\{8\}\)).*/\1/p')
    [ -n "$BID" ] && rsrs forget "$BID" --json >/dev/null 2>&1
    echo "  （注：该条被判直写而非待决，已兜底清理 $BID）"
  fi
else
  echo "SKIP  写探针（默认只读；加 --store 开启，写真库并自动 forget 清理）"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
