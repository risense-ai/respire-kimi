#!/usr/bin/env python3
"""respire 插件自检（Kimi Code 版）—— 结构与规范校验（对齐 Kimi 插件清单规范），零第三方依赖。

用法: python3 scripts/validate_plugin.py   （退出码 0=通过；任一 FAIL=1）
"""
import json
import os
import py_compile
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
failed = False


def ok(msg: str) -> None:
    print(f"OK: {msg}")


def fail(msg: str) -> None:
    global failed
    failed = True
    print(f"FAIL: {msg}", file=sys.stderr)


def read_text(rel: str) -> str:
    p = os.path.join(ROOT, rel)
    if not os.path.isfile(p):
        fail(f"missing {rel}")
        return ""
    with open(p, encoding="utf-8") as f:
        text = f.read()
    if not text.strip():
        fail(f"empty {rel}")
    else:
        ok(rel)
    return text


def read_utf8_strict(rel: str) -> str:
    p = os.path.join(ROOT, rel)
    if not os.path.isfile(p):
        fail(f"missing {rel}")
        return ""
    try:
        with open(p, "rb") as f:
            text = f.read().decode("utf-8")
    except UnicodeDecodeError as e:
        fail(f"{rel} is not valid UTF-8: {e}")
        return ""
    ok(f"{rel} is valid UTF-8")
    return text


def parse_json(rel: str):
    text = read_text(rel)
    if not text:
        return None
    try:
        return json.loads(text)
    except Exception as e:
        fail(f"invalid JSON {rel}: {e}")
        return None


REQUIRED = [
    "kimi.plugin.json",
    "SYSTEM.md",
    "hooks/respire.py",
    "hooks/respire.config.example.json",
    "skills/respire/SKILL.md",
    "commands/recall.md",
    "commands/store.md",
    "commands/sync.md",
    "tests/test_hooks.sh",
    "scripts/validate_plugin.py",
    "README.md",
    "CHANGELOG.md",
    "LICENSE",
]
for rel in REQUIRED:
    read_text(rel)

# manifest 规范（Kimi 官方字段集：name/version/description/keywords/author/homepage/license/
# interface/skills/sessionStart/skillInstructions/systemPrompt(systemPromptPath)/mcpServers/hooks/commands）
manifest = parse_json("kimi.plugin.json")
if manifest:
    name = str(manifest.get("name") or "")
    if name != "respire":
        fail("manifest name must be respire")
    elif not re.match(r"^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*(@[A-Za-z0-9_-]+)?$", name):
        fail(f"manifest name does not match the documented plugin-id regex: {name!r}")
    else:
        ok("manifest name")
    ver = str(manifest.get("version") or "")
    if not re.match(r"^\d+\.\d+\.\d+$", ver):
        fail(f"manifest version must be plain SemVer: {ver!r}")
    else:
        ok(f"manifest version {ver}")
    # 运行代码 VERSION 与发布清单一致（不一致=运行行为与发布声明脱节）
    m_hook = re.search(r'^VERSION\s*=\s*"([^"]+)"', open(os.path.join(ROOT, "hooks", "respire.py"), encoding="utf-8").read(), re.M)
    hook_ver = m_hook.group(1) if m_hook else None
    if ver and hook_ver and ver == hook_ver:
        ok(f"hook VERSION matches manifest ({ver})")
    else:
        fail(f"hook VERSION {hook_ver!r} != manifest version {ver!r}")
    if manifest.get("skills") != "./skills/":
        fail('manifest skills must be "./skills/"')
    else:
        ok("manifest skills pointer")
    sp_path = manifest.get("systemPromptPath")
    if sp_path != "./SYSTEM.md":
        fail('manifest systemPromptPath must be "./SYSTEM.md"')
    else:
        ok("manifest systemPromptPath pointer")
        sp_abs = os.path.join(ROOT, "SYSTEM.md")
        if os.path.isfile(sp_abs):
            sp_size = os.path.getsize(sp_abs)
            if sp_size >= 32 * 1024:
                fail(f"SYSTEM.md must be < 32 KB (systemPromptPath limit), got {sp_size}")
            else:
                ok(f"SYSTEM.md {sp_size}B < 32KB")
    session_start = manifest.get("sessionStart") or {}
    if session_start.get("skill") != "respire":
        fail('manifest sessionStart.skill must be "respire"')
    else:
        ok("manifest sessionStart.skill")
    if manifest.get("commands") != "./commands/":
        fail('manifest commands must be "./commands/"')
    else:
        ok("manifest commands pointer")
    iface = manifest.get("interface") or {}
    for k in ("displayName", "shortDescription", "developerName", "websiteURL"):
        if not iface.get(k):
            fail(f"manifest interface.{k} missing")
    else:
        ok("manifest interface core fields")

# hooks 规范：Kimi 清单内联数组，每规则仅 {event, matcher?, command, timeout?}
hooks = (manifest or {}).get("hooks")
if hooks is not None:
    if not isinstance(hooks, list):
        fail("manifest hooks must be a JSON array")
    elif len(hooks) != 3:
        fail(f"manifest hooks must have exactly 3 rules, got {len(hooks)}")
    else:
        allowed = {"event", "matcher", "command", "timeout"}
        events = []
        for rule in hooks:
            if not isinstance(rule, dict):
                fail("hook rule must be an object")
                continue
            extra = set(rule) - allowed
            if extra:
                fail(f"hook rule has forbidden keys {sorted(extra)} (allowed: event/matcher/command/timeout)")
            events.append(rule.get("event"))
            cmd = str(rule.get("command") or "")
            if not cmd.startswith('python3 "./hooks/respire.py"'):
                fail(f"{rule.get('event')}: command must start with python3 \"./hooks/respire.py\"")
            if '|| python "./hooks/respire.py"' not in cmd:
                fail(f"{rule.get('event')}: command must carry the || python fallback chain")
            t = rule.get("timeout")
            if not isinstance(t, int) or isinstance(t, bool) or t <= 0 or t > 600:
                fail(f"{rule.get('event')}: timeout must be a positive int <= 600, got {t!r}")
        if set(events) != {"SessionStart", "UserPromptSubmit", "Stop"}:
            fail(f"hook events must be exactly SessionStart/UserPromptSubmit/Stop, got {sorted(events)}")
        else:
            ok("hook events set")
        for rule in hooks:
            if rule.get("event") == "SessionStart" and rule.get("matcher") != "startup|resume":
                fail('SessionStart matcher must be "startup|resume"')
        else:
            ok("SessionStart matcher")
        ok("manifest hooks shape")

# SYSTEM.md 与命令文件须为合法 UTF-8
read_utf8_strict("SYSTEM.md")
for c in ("recall", "store", "sync"):
    read_utf8_strict(f"commands/{c}.md")

# SKILL.md frontmatter：name=respire、description 非空
skill = read_text("skills/respire/SKILL.md")
if skill:
    m = re.match(r"^---\n(.*?)\n---\n", skill, re.S)
    if not m:
        fail("SKILL.md missing frontmatter")
    else:
        fm = m.group(1)
        if not re.search(r"^name:\s*respire\s*$", fm, re.M):
            fail("SKILL.md frontmatter name must be respire")
        else:
            ok("SKILL.md name")
        if not re.search(r"^description:\s*\S", fm, re.M):
            fail("SKILL.md frontmatter description must be non-empty")
        else:
            ok("SKILL.md description")

# 主脚本可编译 + 铁律在（fail-open 恒 exit 0；Kimi Stop 阻断 JSON 形状在源码中）
try:
    py_compile.compile(os.path.join(ROOT, "hooks/respire.py"), doraise=True)
    ok("respire.py compiles")
except Exception as e:
    fail(f"respire.py compile: {e}")
src = read_text("hooks/respire.py")
if src:
    if "sys.exit(0)" not in src:
        fail("respire.py must keep fail-open exit 0")
    else:
        ok("fail-open exit present")
    if '"permissionDecision": "deny"' not in src:
        fail('respire.py must contain the Kimi block shape "permissionDecision": "deny"')
    else:
        ok("Kimi deny JSON present")

# 宿主特异目录禁入（Kimi 版单一 kimi.plugin.json，不携带其他宿主清单）
for d in (".codex-plugin", ".claude-plugin", ".qoder-plugin", ".codebuddy-plugin"):
    if os.path.exists(os.path.join(ROOT, d)):
        fail(f"host-specific dir must not be present: {d}")
else:
    ok("no foreign host dirs")

# 敏感模式扫描（分发前自检）
SECRET = re.compile(r"sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY")
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in {".git", "__pycache__", "node_modules"}]
    for fn in filenames:
        if fn.endswith((".pyc", ".webp", ".png", ".jpg")):
            continue
        p = os.path.join(dirpath, fn)
        try:
            with open(p, encoding="utf-8", errors="ignore") as f:
                if SECRET.search(f.read()):
                    fail(f"secret-like pattern in {os.path.relpath(p, ROOT)}")
        except Exception:
            pass
ok("secret scan done")

print("----")
if failed:
    print("VALIDATE: FAIL")
    sys.exit(1)
print("VALIDATE: PASS")
sys.exit(0)
