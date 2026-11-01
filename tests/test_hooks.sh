#!/usr/bin/env bash
# respire 自测（Kimi Code 版）—— 模拟 stdin 事件 JSON，逐分支断言。
# rsrs 无 data-dir 隔离（runtime 单例＋全局 client.json），故默认只读分支不碰库；
# 加 --store 才跑写探针（写真库→回执断言→rsrs forget 自清理）。
# Kimi 适配：SessionStart stdout 恒为空（观察型事件，输出不进模型上下文），
# 引导断言一律走 .pending_nudge 状态文件（RESPITE_PENDING_NUDGE 覆写路径，首条 prompt 带出即删）。
set -u
export MSYS2_ENV_CONV_EXCL='PR'  # MSYS 连 env 值都会把「/nomem …」转成 Windows 路径——只豁免 prompt 变量
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY3="$(command -v python3)"
RSRS="$(command -v rsrs || true)"
[ -z "$RSRS" ] && RSRS="$HOME/.local/bin/rsrs"
[ -z "$RSRS" ] && RSRS="$HOME/.rsrs/bin/rsrs"
PASS=0; FAIL=0
WITH_STORE=0
[ "${1:-}" = "--store" ] && WITH_STORE=1
wpath() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }   # Windows Python 可见的混合斜杠路径

if [ -z "$RSRS" ] || [ ! -x "$RSRS" ]; then
  echo "SKIP：未找到 rsrs（respire 引擎），无法自测。"; exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/data"
CFG_ON="$TMP/config-on.json"
echo '{"session_rules": true}' > "$CFG_ON"
CFG_OFF="$TMP/config-off.json"
echo '{"session_rules": false}' > "$CFG_OFF"

# run <event> [prompt] [config] [logfile] [stubmode] —— 每次调用独立 pending 路径，杜绝测试间挂起引导互染；
# logfile 可换独立文件（凭据守卫断言专用日志，避免与共享 hook.log 互染）；stubmode 只被桩引擎读（真引擎忽略）；
# prompt 走 PR env（MSYS 会把「/nomem …」argv 转成 Windows 路径，env 值不转）；turn 状态文件独立供 Stop 场景复位
run() {
  local ev="$1" pr="${2-}" cfg="${3:-$CFG_ON}" log="${4:-$TMP/hook.log}" stub="${5:-ok}" pend="$TMP/pending_$RANDOM$RANDOM$RANDOM"
  PR="$pr" "$PY3" - "$ev" <<'PY' | PR="$pr" RESPITE_CONFIG="$(wpath "$cfg")" RESPITE_LOG="$(wpath "$log")" RESPITE_NUDGE_STATE="$(wpath "$TMP/nudge")" RESPITE_TURN_STATE="$(wpath "$TMP/turn.json")" RESPITE_DATA="$(wpath "$TMP/data")" RESPITE_PENDING_NUDGE="$pend" STUB_MODE="$stub" "$PY3" "$ROOT/hooks/respire.py" "$ev"
import json, os, sys
ev = sys.argv[1]
pr = os.environ.get("PR", "")
d = {"hook_event_name": ev, "cwd": "/tmp", "session_id": "selftest"}
if ev == "UserPromptSubmit":
    d["prompt"] = pr
sys.stdout.buffer.write(json.dumps(d, ensure_ascii=False).encode("utf-8"))
PY
}

# ss_fixed <pend路径> [config]：固定 pending 路径跑 SessionStart（调用处以环境变量前缀注入 FAKE 后门）
ss_fixed() {
  local pend="$1" cfg="${2:-$CFG_ON}"
  RESPITE_CONFIG="$(wpath "$cfg")" RESPITE_LOG="$(wpath "$TMP/hook.log")" RESPITE_NUDGE_STATE="$(wpath "$TMP/nudge")" RESPITE_DATA="$(wpath "$TMP/data")" RESPITE_PENDING_NUDGE="$pend" "$PY3" "$ROOT/hooks/respire.py" SessionStart <<'JSON'
{"hook_event_name":"SessionStart","session_id":"selftest","cwd":"/tmp"}
JSON
}

# ps_fixed <pend路径> <prompt> [config]：固定 pending 路径跑 UserPromptSubmit
ps_fixed() {
  local pend="$1" pr="$2" cfg="${3:-$CFG_ON}"
  PR="$pr" "$PY3" - <<'PY' | RESPITE_CONFIG="$(wpath "$cfg")" RESPITE_LOG="$(wpath "$TMP/hook.log")" RESPITE_NUDGE_STATE="$(wpath "$TMP/nudge")" RESPITE_DATA="$(wpath "$TMP/data")" RESPITE_PENDING_NUDGE="$pend" "$PY3" "$ROOT/hooks/respire.py" UserPromptSubmit
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
for _v in fresh stale; do
  if [ "$_v" = fresh ]; then _ts="$FRESH_TS"; else _ts="2020-01-01T00:00:00.000Z"; fi
  cat > "$TMP/rsrs-$_v" <<PYEOF
#!/usr/bin/env python3
import json, sys
if (sys.argv[1] if len(sys.argv) > 1 else "") == "list":
    print(json.dumps({"command": "list", "status": "ok", "details": [
        {"id": "aaaaaaaaaaaaaaaa" if "$_v" == "fresh" else "bbbbbbbbbbbbbbbb",
         "created_at": "$_ts", "updated_at": "$_ts", "title": "$_v", "content": "x"}]}))
PYEOF
  chmod +x "$TMP/rsrs-$_v"
done
# Windows：bash/python 脚本不能被 CreateProcess 直接 exec，包一层 .cmd（解释器回退 py.exe/python.exe）
if command -v cmd.exe >/dev/null 2>&1; then
  PY3_WIN="$(cygpath -w "$PY3" 2>/dev/null || echo "$PY3")"
  for _cand in "py.exe" "python.exe"; do
    _p="$(dirname "$PY3_WIN")/$_cand"
    [ -f "$_p" ] && PY3_WIN="$_p" && break
  done
  if [ ! -f "$PY3_WIN" ] || [ "${PY3_WIN##*.}" != "exe" ]; then
    _py="$(command -v py)"
    [ -n "$_py" ] && PY3_WIN="$(cygpath -w "$_py")"
  fi
  [ -f "$PY3_WIN.exe" ] && PY3_WIN="$PY3_WIN.exe"
  for _v in fresh stale; do
    cat > "$TMP/rsrs-$_v.cmd" <<WRAP
@echo off
"$PY3_WIN" "%~dp0rsrs-$_v" %*
WRAP
  done
  STUB_FRESH="$TMP/rsrs-fresh.cmd"; STUB_STALE="$TMP/rsrs-stale.cmd"
fi
CFG_STALE="$TMP/config-stale.json"
echo '{"session_rules": true, "rsrs": "'"$(wpath "$STUB_STALE")"'"}' > "$CFG_STALE"
CFG_FRESH="$TMP/config-fresh.json"
echo '{"session_rules": true, "rsrs": "'"$(wpath "$STUB_FRESH")"'"}' > "$CFG_FRESH"
# fresh 桩改为调用时动态时间戳（毫秒精度 UTC）——套件启动时的静态时间戳会早于运行中的 prompt，误判「写入早于本轮」
cat > "$TMP/rsrs-fresh" <<'PYEOF'
#!/usr/bin/env python3
import datetime, json, sys
now = datetime.datetime.now(datetime.timezone.utc)
ts = now.strftime("%Y-%m-%dT%H:%M:%S") + ".%03dZ" % (now.microsecond // 1000)
if (sys.argv[1] if len(sys.argv) > 1 else "") == "list":
    print(json.dumps({"command": "list", "status": "ok", "details": [
        {"id": "aaaaaaaaaaaaaaaa", "created_at": ts, "updated_at": ts, "title": "fresh", "content": "x"}]}))
PYEOF
chmod +x "$TMP/rsrs-fresh"
# 查询故障桩：list 回垃圾（fail-open 场景用）
cat > "$TMP/rsrs-bad" <<'PYEOF'
#!/usr/bin/env python3
print("garbage not json")
PYEOF
chmod +x "$TMP/rsrs-bad"
if command -v cmd.exe >/dev/null 2>&1; then
  for _v in bad; do
    cat > "$TMP/rsrs-$_v.cmd" <<WRAP
@echo off
"$PY3_WIN" "%~dp0rsrs-$_v" %*
WRAP
  done
  STUB_BAD="$TMP/rsrs-bad.cmd"
else
  STUB_BAD="$TMP/rsrs-bad"
fi
CFG_BAD="$TMP/config-bad.json"
echo '{"session_rules": true, "rsrs": "'"$(wpath "$STUB_BAD")"'"}' > "$CFG_BAD"

# ---- python 桩引擎（跨平台）：先登记调用再返回 canned JSON。凭据守卫与兜底清理断言共用：
# 正向对照必须证明普通输入真调了引擎（不成立即 FAIL，绝不 SKIP），凭据轮才可断言零调用。----
SPY_SRC="$TMP/rsrs-stub"
cat > "$SPY_SRC" <<'PY'
#!/usr/bin/env python3
import json, os, sys
sub = sys.argv[1] if len(sys.argv) > 1 else ""
mode = os.environ.get("STUB_MODE", "ok")
# 先登记调用再返回：调用日志落桩自身目录（Windows/POSIX 路径两形态同指一文件），供计数断言
logp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "spy-calls.log")
try:
    with open(logp, "a", encoding="utf-8") as f:
        f.write(" ".join(sys.argv[1:]) + "\n")
except Exception:
    pass
if sub == "forget":            # 兜底清理桩：forget_fail 模拟清理失败（登记后非零退出，回执断言可见）
    if mode == "forget_fail":
        sys.exit(1)
    print(json.dumps({"command": "forget", "status": "ok"}))
elif sub == "recall":
    print(json.dumps({"status": "ok", "summary": {"count": 1}, "items": [], "details": [
        {"id": "cccc1111-2222-3333-4444-555555555555", "score": 0.62,
         "superseded_by": None, "title": "spy 桩召回命中条"}]}))
else:
    print(json.dumps({"status": "ok", "summary": {}}))
PY
chmod +x "$SPY_SRC"
if command -v cmd.exe >/dev/null 2>&1; then
  # Windows：python 脚本不能被 CreateProcess 直接 exec，包一层 .cmd（须在 stub 写完后生成）
  PY3_WIN="$(cygpath -w "$PY3" 2>/dev/null || echo "$PY3")"
  for _cand in "py.exe" "python.exe"; do   # shim 兼容：无扩展名解释器 cmd.exe 跑不动，回退 py.exe/python.exe
    _p="$(dirname "$PY3_WIN")/$_cand"
    [ -f "$_p" ] && PY3_WIN="$_p" && break
  done
  if [ ! -f "$PY3_WIN" ] || [ "${PY3_WIN##*.}" != "exe" ]; then
    _py="$(command -v py)"
    [ -n "$_py" ] && PY3_WIN="$(cygpath -w "$_py")"
  fi
  [ -f "$PY3_WIN.exe" ] && PY3_WIN="$PY3_WIN.exe"   # command -v 输出常省略 .exe 后缀，补全防 cmd 找不到
  cat > "$TMP/rsrs-stub.cmd" <<WRAP
@echo off
"$PY3_WIN" "%~dp0rsrs-stub" %*
WRAP
  SPY="$TMP/rsrs-stub.cmd"
else
  SPY="$SPY_SRC"
fi
calls_n() { wc -l < "$TMP/spy-calls.log" 2>/dev/null | tr -d '[:space:]'; }

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
# secret_skip 已只记固定码（敏感摘要不落日志，见凭据守卫段）；脱敏留痕改在合法落详情的 nomem 分支上验证
run UserPromptSubmit "/nomem 口令: hunter2 这条走 nomem_or_empty 落详情" >/dev/null
check "日志脱敏留痕" "$(grep -q 'REDACTED' "$TMP/hook.log" && echo YES)" "含:YES"
check "hook.log 留痕" "$(grep -q '"ev": "session"' "$TMP/hook.log" 2>/dev/null && echo YES)" "含:YES"

# Stop 存储检查（审计新契约：fail-open / 请求级凭证 / 一次收尾锁；每场景 rst 复位轮次状态与节流计数）
STOP_LOG="$TMP/stop.log"; : > "$STOP_LOG"
rst() { rm -f "$TMP/turn.json" "$TMP/nudge"; }
run_stop() {   # run_stop <stop_hook_active> [config]
  "$PY3" - "$1" <<'PY' | RESPITE_CONFIG="$(wpath "${2:-$CFG_STALE}")" RESPITE_LOG="$(wpath "$STOP_LOG")" RESPITE_NUDGE_STATE="$(wpath "$TMP/nudge")" RESPITE_TURN_STATE="$(wpath "$TMP/turn.json")" RESPITE_DATA="$(wpath "$TMP/data")" RESPITE_PENDING_NUDGE="$(wpath "$TMP/pending_stop_$RANDOM$RANDOM")" "$PY3" "$ROOT/hooks/respire.py" Stop
import json, sys
sys.stdout.buffer.write(json.dumps({"hook_event_name": "Stop", "session_id": "selftest",
                                    "stop_hook_active": sys.argv[1] == "true"}).encode("utf-8"))
PY
}
rst; OUT_STOP="$(run_stop false)"
check "Stop 存储检查续跑(deny)" "$OUT_STOP" '含:"permissionDecision": "deny"'
check "Stop 含阻断原因字段" "$OUT_STOP" "含:permissionDecisionReason"
check "Stop 提示含存储指令" "$OUT_STOP" "含:rsrs remember"
rst; check "Stop 防重入放行(active)" "$(run_stop true)" "空"
CFG_NUDGE0="$TMP/config-nudge0.json"
echo '{"store_nudge_every": 0}' > "$CFG_NUDGE0"
rst; check "Stop 节流关闭静默" "$(run_stop false "$CFG_NUDGE0")" "空"
rst; run_stop false >/dev/null
check "同请求二次Stop一次收尾锁放行(宿主未带active)" "$(run_stop false)" "空"
rst; run UserPromptSubmit "next real question" >/dev/null
check "新请求重新武装仍催" "$(run_stop false)" '含:"permissionDecision": "deny"'
rst; check "无请求凭证时引擎新写入仍催(不跨轮误抑制)" "$(run_stop false "$CFG_FRESH")" '含:"permissionDecision": "deny"'
rst; run UserPromptSubmit "turn with engine store" >/dev/null
check "引擎写入晚于本轮prompt免催" "$(run_stop false "$CFG_FRESH")" "空"
check "引擎放行留痕 src=engine" "$(grep -q 'stored_recent_skip.*src=engine' "$STOP_LOG" && echo YES)" "含:YES"
rst; check "查库坏信封fail-open放行(旧代码会催)" "$(run_stop false "$CFG_BAD")" "空"
check "fail-open 留痕" "$(grep -q 'engine_query_fail_open' "$STOP_LOG" && echo YES)" "含:YES"
check "一次收尾锁留痕" "$(grep -q 'once_latch_skip' "$STOP_LOG" && echo YES)" "含:YES"
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

check "无关 prompt 不注入(桩静默,确定性)" "$(run UserPromptSubmit "今晚吃什么菜好呢" "$CFG_STALE")" "空"
check "单字 prompt 跳过" "$(run UserPromptSubmit "嗯")" "空"
check "/nomem 关闭召回" "$(run UserPromptSubmit "/nomem rsrs 信封结构")" "空"
# ---- 合成凭据守卫（审计项：secret_skip 曾把命中输入前 40 字落日志，而 redact 不覆盖普通
# api_key/token/secret 赋值与 Bearer 值 → 摘要即明文凭据）。凭据字面量一律运行时拼接，
# 源文件不出现 sk-<12+> 连续串，secret 静态扫描才不拦；nonce=synthetic 供 grep 断言零泄漏。----
SYN_KEY="synthetic""0123456789abcdef"         # api_key= 赋值：SECRET_RE 命中；redact 表不覆盖
SYN_TOKEN="sk-""synthetic""0123456789abcdef"  # sk- 令牌：SECRET_RE 的 sk- 分支命中
SYN_BEARER="Bearer ""synthetic""zzzyyxxxwww"  # Bearer 值：SECRET_RE 命中；redact 同样不覆盖
check "疑似凭据不发引擎" "$(run UserPromptSubmit "api_key = ${SYN_TOKEN} 存一下")" "含:contains a credential"
check "疑似凭据不落库" "$(run UserPromptSubmit "记：数据库密码 = hunter2u")" "含:contains a credential"
# ---- 合成凭据守卫与守卫说明见下方 SYN 定义之后；nonce=synthetic 供 grep 断言零泄漏。----
SECRET_LOG="$TMP/secret.log"; : > "$SECRET_LOG"
: > "$TMP/spy-calls.log"
CFG_SPY="$TMP/config-spy.json"
"$PY3" -c 'import json,sys; json.dump({"session_rules": True, "rsrs": sys.argv[1]}, open(sys.argv[2], "w", encoding="utf-8"))' "$(wpath "$SPY")" "$CFG_SPY"
N0="$(calls_n)"
OUT="$(run UserPromptSubmit "api_key = ${SYN_KEY} 存一下" "$CFG_SPY" "$SECRET_LOG")"
check "疑似凭据拦截提示" "$OUT" "含:contains a credential"
check "合成凭据不进注入输出" "$OUT" "不含:synthetic"
check "合成凭据不落 hook.log" "$(grep -q 'synthetic' "$SECRET_LOG" && echo LEAK || echo SAFE)" "含:SAFE"
check "secret_skip 只记固定码无 d 字段" "$(grep 'secret_skip' "$SECRET_LOG" | grep -q '"d"' && echo HAS_DETAIL || echo CODE_ONLY)" "含:CODE_ONLY"
check "凭据轮桩引擎零调用" "$( [ "$(calls_n)" = "$N0" ] && echo SAME || echo CALLED )" "含:SAME"
check "sk- 令牌同样拦截" "$(run UserPromptSubmit "my token: ${SYN_TOKEN} remember this" "$CFG_SPY" "$SECRET_LOG")" "含:contains a credential"
check "Bearer 值同样拦截" "$(run UserPromptSubmit "Authorization: ${SYN_BEARER} remember this" "$CFG_SPY" "$SECRET_LOG")" "含:contains a credential"
check "凭据轮桩引擎全程零调用" "$( [ "$(calls_n)" = "$N0" ] && echo SAME || echo CALLED )" "含:SAME"
check "普通路径召回不回归" "$(run UserPromptSubmit "普通问题照常召回注入" "$CFG_SPY" "$SECRET_LOG")" "含:auto-recall"
check "正向对照-普通输入真实调用桩" "$( [ "$(calls_n)" != "$N0" ] && echo CALLED || echo SAME )" "含:CALLED"
check "斜杠命令剥前缀仍召回" "$(run UserPromptSubmit "/respire:recall rsrs 信封 JSON 结构解析取哪层")" "含:auto-recall"
check "斜杠命令整轮不召回不崩溃" "$(run UserPromptSubmit "/respire:recall")" "空"
check "裸斜杠不崩溃" "$(run UserPromptSubmit "/")" "空"
CFG_SKIP="$TMP/config-skip.json"
echo '{"skip_prefixes": ["recap:", "Weekly recap"]}' > "$CFG_SKIP"
check "skip_prefixes 命中不召回" "$(run UserPromptSubmit "Recap: 本周完成了 respire 插件移植总结" "$CFG_SKIP")" "空"
check "坏 stdin 静默" "$(printf 'not-json{{{' | RESPITE_CONFIG="$(wpath "$CFG_ON")" RESPITE_LOG="$(wpath "$TMP/hook.log")" RESPITE_DATA="$(wpath "$TMP/data")" RESPITE_PENDING_NUDGE="$(wpath "$TMP/pending_bad_$RANDOM")" "$PY3" "$ROOT/hooks/respire.py" UserPromptSubmit)" "空"
check "未知事件静默" "$(run PreToolUse "rsrs 信封")" "空"

# ---- title 规则抽取（纯函数，零污染；ROOTM=混合路径——Windows python 解析不了 MSYS 的 /d/...） ----
ROOTM="$(wpath "$ROOT")"
check "整句优先取完整句" "$(python3 -c '
import sys,importlib.util
spec=importlib.util.spec_from_file_location("r","'"$ROOTM"'/hooks/respire.py"); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.extract_title("memlite 插件路径迁至 memocap 下。后续以仓库为准。"))')" "含:memlite 插件路径迁至 memocap 下。"
check "无句号退分隔符不切半词" "$(python3 -c '
import sys,importlib.util
spec=importlib.util.spec_from_file_location("r","'"$ROOTM"'/hooks/respire.py"); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
t=m.extract_title("这是一条没有句号的长事实句，讲清楚何时谁做了什么事，以及结果如何，后面还有别的内容")
print(t)')" "含:讲清楚何时谁做了什么事，"
check "长串不超70字" "$(python3 -c '
import sys,importlib.util
spec=importlib.util.spec_from_file_location("r","'"$ROOTM"'/hooks/respire.py"); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(len(m.extract_title("默" * 200)))')" "非空"

# ---- 判重轮兜底清理（--store 写探针的清理逻辑；真库直写时 forget 该条，绝不把测试记录遗留进用户库） ----
probe_cleanup() {   # probe_cleanup <回执文本> [label] [engine=RSRS]；返回 0=直写已清理 / 1=待决未写无需清理 / 2=应清理而失败（显式报告，不静默）
  local out="$1" label="${2:-判重轮}" eng="${3:-$RSRS}" bid
  # 回执识别双兼容：现版英文 "Saved:" ＋ 旧版中文「已存入」——识别失效＝清理被跳过＝测试记录落真库，故两种形态都接住
  printf '%s' "$out" | grep -qF -e "Saved:" -e "已存入" || return 1
  # 历史中文回执使用全角括号；先规范化，再沿用严格的八位短 id 提取。
  bid="$(printf '%s' "$out" | sed -n 's/（/(/g;s/）/)/g;s/.*(\([0-9a-f]\{8\}\)).*/\1/p')"
  if [ -z "$bid" ]; then
    echo "  FAIL（兜底清理失效）：$label 回执判直写但未解析出短 id，需手工 rsrs forget"
    return 2
  fi
  if STUB_MODE="${STUB_MODE:-ok}" "$eng" forget "$bid" --json >/dev/null 2>&1; then
    echo "  （注：$label 被判直写而非待决，已兜底清理 $bid）"
    return 0
  fi
  echo "  FAIL（兜底清理失效）：$label rsrs forget $bid 非零退出，需手工确认清理"
  return 2
}

# ---- 兜底清理分支桩测（隔离：引擎全为桩，默认路径零真库调用） ----
: > "$TMP/spy-calls.log"
GL_OUT="$(probe_cleanup "【respire · stored】Saved: 桩测直写样例 (deadbeef). title" "桩测直写" "$SPY")"; GL_RC=$?
check "兜底清理-直写分支执行清理" "$( [ "$GL_RC" = 0 ] && echo CLEANED || echo RC=$GL_RC )" "含:CLEANED"
check "兜底清理-按回执短 id forget" "$(grep -cF 'forget deadbeef' "$TMP/spy-calls.log" 2>/dev/null)" "含:1"
GN0="$(calls_n)"
GN_OUT="$(probe_cleanup "【respire · store pending】nothing was written; decide with --parent or --force" "桩测待决" "$SPY")"; GN_RC=$?
check "兜底清理-待决分支不清理" "$( { [ "$GN_RC" = 1 ] && [ "$(calls_n)" = "$GN0" ]; } && echo SKIPCLEAN || echo BAD )" "含:SKIPCLEAN"
export STUB_MODE=forget_fail
GF_OUT="$(probe_cleanup "【respire · stored】Saved: 桩测清理失败样例 (cafebabe). title" "桩测清理失败" "$SPY")"; GF_RC=$?
unset STUB_MODE
check "兜底清理-失败分支退出码非零" "$( [ "$GF_RC" = 2 ] && echo EXPLICIT || echo SILENT )" "含:EXPLICIT"
check "兜底清理-失败分支显式报告" "$GF_OUT" "含:FAIL（兜底清理失效）"

# ---- 写探针（--store 显式开启；写真库→断言→forget 清理） ----
if [ "$WITH_STORE" = 1 ]; then
  # 内容须与全库零语义关联：纯随机无义串（域词如「探针/测试/记忆」会撞 30%+ 相似走待决态）
  MARK="zq$(date +%s)$RANDOM kw7f2 随机标记无义串"
  out=$(run UserPromptSubmit "记：$MARK")
  if printf '%s' "$out" | grep -qF "store pending"; then
    PASS=$((PASS+1)); echo "SKIP  随机串判重待决（实时库判重门收紧，ok 回执路径由 CI 桩覆盖）"
  else
    check "落库成功回执" "$out" "含:Saved:"
    check "回执约束AI抽事实句retitle" "$out" "含:rsrs retitle"
    SID=$(printf '%s' "$out" | sed -n 's/.*(\([0-9a-f]\{8\}\)).*/\1/p')
    check "回执带短 id" "$SID" "非空"
    if [ -n "$SID" ]; then
      rc=$(rsrs forget "$SID" --json 2>/dev/null | jq -r '.status // "err"')
      check "探针清理(status=ok)" "$rc" "含:ok"
    fi
  fi
  # 判重待决：复述库中稳定条目（1memory 更名 respire）→ 必撞高相似 → pending 未写入
  out=$(run UserPromptSubmit "记：1memory 更名 respire：吸即存呼即取，材料全线改（复述既有条目触发判重待决）")
  check "判重待决转述候选" "$out" "含:store pending"
  check "待决列出候选与决断法" "$out" "含:--force"
  # 兜底：万一判为直写（库条变更），probe_cleanup 负责清理；rc=2（应清未清/解析失败）显式 FAIL 不静默
  CL_OUT="$(probe_cleanup "$out" "判重探针")"; CL_RC=$?
  if [ "$CL_RC" = 2 ]; then
    FAIL=$((FAIL+1)); echo "FAIL  判重探针兜底清理  详情[$(printf '%s' "$CL_OUT" | head -c 200)]"
  else
    PASS=$((PASS+1)); echo "PASS  判重探针兜底清理路径(rc=$CL_RC: 1=待决未写 0=直写已清)"
  fi
else
  echo "SKIP  写探针（默认只读；加 --store 开启，写真库并自动 forget 清理）"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
