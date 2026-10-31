#!/usr/bin/env python3
"""Portable, isolated hook tests. No real engine discovery or user data access."""
import json
import os
import re
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SECRET = 'sk-' + 'q7xkwm2vbnr8tzc41p9e'


def allowed_process(executable, argv, expected_argv, windows):
    """Match only the complete expected invocation, including all arguments.

    CPython's Windows audit event receives executable=None and the already
    list2cmdline-encoded string; POSIX receives an executable and an argv list.
    """
    if executable != expected_argv[0] and not (windows and executable is None):
        return False
    if isinstance(argv, (list, tuple)):
        return list(argv) == expected_argv
    return windows and isinstance(argv, str) and argv == subprocess.list2cmdline(expected_argv)


# Run the unmodified hook with a subprocess allowlist. A failure cannot silently
# fall through to a real rsrs executable, even on machines where one is installed.
LAUNCHER = r'''
import json, os, pathlib, runpy, sys
case = pathlib.Path(os.environ['RESPITE_CONFIG']).resolve().parent
expected = os.environ['TEST_ENGINE']
expected_argv = json.loads(os.environ['TEST_EXPECTED_ARGV'])
assert expected_argv[0] == expected
config = json.loads(pathlib.Path(os.environ['RESPITE_CONFIG']).read_text(encoding="utf-8"))
assert config['rsrs'] == expected and os.access(expected, os.X_OK)
sys.path.insert(0, str(pathlib.Path(os.environ['TEST_HOOK']).parents[1] / 'tests'))
from test_ci import allowed_process
def audit(event, args):
    if event == 'subprocess.Popen':
        executable, argv, cwd, env = args
        if not allowed_process(executable, argv, expected_argv, os.name == 'nt'):
            pathlib.Path(os.environ['TEST_DENIED']).write_text('unexpected subprocess')
            raise SystemExit(91)
    elif event.startswith('socket.') or event in ('os.system', 'os.posix_spawn', 'os.exec'):
        pathlib.Path(os.environ['TEST_DENIED']).write_text('unexpected external action')
        raise SystemExit(92)
sys.addaudithook(audit)
sys.argv = [os.environ['TEST_HOOK'], os.environ['TEST_EVENT']]
runpy.run_path(sys.argv[0], run_name='__main__')
'''


class CredentialGuard(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='kimi-guard-')
        self.addCleanup(self.temp.cleanup)
        self.case = Path(self.temp.name)
        self.spy = self.case / 'spy.py'
        self.calls = self.case / 'calls.jsonl'
        self.log = self.case / 'hook.log'
        self.denied = self.case / 'denied'
        self.spy.write_text(r'''import json, os, sys, datetime
with open(os.environ['TEST_CALLS'], 'a', encoding='utf-8') as f:
    f.write(json.dumps(sys.argv[1:]) + '\n')
sub = sys.argv[1]
mode = os.environ.get('STUB_MODE', 'ok')
if mode == 'dead': sys.exit(7)
if mode == 'malformed': print('not json'); sys.exit(0)
if sub == 'recall':
    print(json.dumps({'status':'ok','details':[{'id':'cccccccccccccccc','title':'spy','score':0.9}]}))
elif sub == 'remember':
    print(json.dumps({'status':'ok','summary':{'id':'dddddddddddddddd'}}))
elif sub == 'status':
    print(json.dumps({'status':'ok','summary':{'session':{'has_token':True,'user':'stub'},'local_total':42}}))
elif sub == 'list':
    ts = datetime.datetime.now(datetime.timezone.utc).isoformat() if mode == 'recent' else '2020-01-01T00:00:00Z'
    print(json.dumps({'status':'fail'} if mode == 'failed' else {'status':'ok','details':[{'id':'record','updated_at':ts}]}))
else: sys.exit(1)
''', encoding="utf-8")
        if os.name == 'nt':
            self.engine = self.case / 'rsrs-spy.cmd'
            self.engine.write_text(f'@echo off\n"{sys.executable}" "{self.spy}" %*\n', encoding="utf-8")
        else:
            self.engine = self.case / 'rsrs-spy'
            self.engine.write_text(f'#!{sys.executable}\n' + self.spy.read_text(encoding="utf-8"), encoding="utf-8")
        self.engine.chmod(0o700)
        self.config = self.case / 'config.json'
        self.config.write_text(json.dumps({'rsrs': str(self.engine), 'session_rules': True}), encoding="utf-8")
        self.launcher = self.case / 'launcher.py'
        self.launcher.write_text(LAUNCHER, encoding="utf-8")
        self.env = {k: v for k, v in os.environ.items()
                    if k.upper() in {'PATH', 'SYSTEMROOT', 'WINDIR', 'PATHEXT', 'TEMP', 'TMP', 'COMSPEC'}}
        self.env.update(RESPITE_CONFIG=str(self.config), RESPITE_LOG=str(self.log),
                        HOME=str(self.case / 'home'), USERPROFILE=str(self.case / 'home'),
                        XDG_CONFIG_HOME=str(self.case / 'config'),
                        XDG_DATA_HOME=str(self.case / 'data'),
                        XDG_CACHE_HOME=str(self.case / 'cache'),
                        RESPITE_NUDGE_STATE=str(self.case / 'nudge'),
                        RESPITE_PENDING_NUDGE=str(self.case / 'pending'),
                        RESPITE_DATA=str(self.case / 'plugin-data'),
                        KIMI_PLUGIN_DATA=str(self.case / 'plugin-data'),
                        TEST_ENGINE=str(self.engine), TEST_CALLS=str(self.calls),
                        TEST_DENIED=str(self.denied), TEST_HOOK=str(ROOT / 'hooks/respire.py'),
                        PYTHONDONTWRITEBYTECODE='1', PYTHONUTF8='1')

    def call(self, prompt='', event='UserPromptSubmit', mode='ok', active=False, every=1):
        self.config.write_text(json.dumps({'rsrs':str(self.engine), 'session_rules':True,
                                          'store_nudge_every':every}), encoding="utf-8")
        if event == 'Stop':
            args = ['list','--limit','3','--json']
        elif event == 'SessionStart':
            args = ['status','--json']
        elif prompt.startswith(('记：','store:')):
            content = prompt.replace('：',':',1).split(':',1)[1].strip()
            args = ['remember',content,'--title',content,'--importance','important','--json']
        else:
            args = ['recall',prompt,'--limit','5','--titles','--json']
        env = dict(self.env, TEST_EXPECTED_ARGV=json.dumps([str(self.engine)] + args),
                   TEST_EVENT=event, STUB_MODE=mode)
        result = subprocess.run([sys.executable, str(self.launcher)],
                                input=json.dumps({'prompt':prompt,'hook_event_name':event,
                                                  'stop_hook_active':active}), text=True,
                                encoding='utf-8', capture_output=True, env=env,
                                cwd=self.case, timeout=20)
        self.assertFalse(self.denied.exists(), 'Isolation denied an external action')
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def recorded(self):
        return [json.loads(line) for line in self.calls.read_text(encoding="utf-8").splitlines()] if self.calls.exists() else []

    def positive_control(self):
        before = len(self.recorded())
        output = self.call('rsrs envelope structure recall')
        self.assertEqual(len(self.recorded()), before + 1, 'Live spy must record normal input')
        self.assertEqual(self.recorded()[-1][0], 'recall')
        self.assertIn('auto-recall', output)
        self.assertIn('matched 1 item(s)', output)
        self.assertIn('[0.90] spy', output)

    def test_normal_input_requires_live_spy(self):
        self.positive_control()

    def test_credential_has_zero_calls_and_no_disclosure(self):
        self.positive_control()
        before = self.recorded()
        output = self.call('api_key = ' + SECRET + ' store this')
        self.assertIn('contains a credential', output)
        self.assertEqual(self.recorded(), before)
        self.assertNotIn(SECRET, output)
        self.assertNotIn(SECRET, self.log.read_text(encoding="utf-8"))
        entries = [json.loads(line) for line in self.log.read_text(encoding="utf-8").splitlines()]
        skipped = [entry for entry in entries if entry['out'] == 'secret_skip']
        self.assertEqual(len(skipped), 1)
        self.assertNotIn('d', skipped[0])

    def test_store_prefix_credential_is_blocked(self):
        self.positive_control()
        before = self.recorded()
        output = self.call('记：数据库密码 = hunter2u')
        self.assertIn('contains a credential', output)
        self.assertEqual(self.recorded(), before)
        self.assertNotIn('hunter2u', output + self.log.read_text(encoding="utf-8"))

    def test_dead_spy_must_fail_positive_control(self):
        # A valid executable that does not record/return JSON must never count as
        # proof of a zero-call guard. This explicitly exercises that failure.
        if os.name == 'nt':
            self.spy.write_text('import sys\nsys.exit(7)\n', encoding="utf-8")
        else:
            self.engine.write_text(f'#!{sys.executable}\nimport sys\nsys.exit(7)\n', encoding="utf-8")
        with self.assertRaisesRegex(AssertionError, 'Live spy must record normal input'):
            self.positive_control()

    def test_session_uses_only_stub_status(self):
        out = self.call(event='SessionStart')
        self.assertEqual(out, '')
        pending = self.case/'pending'
        self.assertTrue(pending.exists())
        self.assertIn('rsrs model activate', pending.read_text(encoding='utf-8'))
        self.assertIn('[0.90] spy', self.call('ordinary prompt consumes pending'))
        self.assertFalse(pending.exists())
        self.assertEqual([args[0] for args in self.recorded()], ['status','recall'])

    def test_explicit_store_receipt_comes_from_stub(self):
        out = self.call('store: durable fixture fact')
        self.assertIn('respire · stored', out)
        self.assertIn('retitle dddddddd', out)
        self.assertEqual(self.recorded()[-1][0], 'remember')

    def test_stop_deny_and_reentry_zero_calls(self):
        out = json.loads(self.call(event='Stop'))
        self.assertEqual(out['hookSpecificOutput']['permissionDecision'], 'deny')
        self.assertIn('rsrs remember', out['hookSpecificOutput']['permissionDecisionReason'])
        before, count = self.recorded(), (self.case / 'nudge').read_text(encoding="utf-8")
        self.assertEqual(self.call(event='Stop', active=True), '')
        self.assertEqual(self.recorded(), before)
        self.assertEqual((self.case / 'nudge').read_text(encoding="utf-8"), count)

    def test_stop_every_three_and_disabled_zero_calls(self):
        for number in range(1, 7):
            out = self.call(event='Stop', every=3)
            if number in (3, 6):
                self.assertEqual(json.loads(out)['hookSpecificOutput']['permissionDecision'], 'deny')
            else:
                self.assertEqual(out, '')
        self.assertEqual(len(self.recorded()), 2)
        before = self.recorded()
        self.assertEqual(self.call(event='Stop', every=0), '')
        self.assertEqual(self.recorded(), before)
        self.assertEqual((self.case / 'nudge').read_text(encoding="utf-8"), '6')

    def test_stop_recent_stale_and_failed_query(self):
        self.assertEqual(self.call(event='Stop', mode='recent'), '')
        for mode in ('ok', 'failed'):
            self.assertEqual(json.loads(self.call(event='Stop', mode=mode))
                             ['hookSpecificOutput']['permissionDecision'], 'deny')

    def test_stop_after_hook_store_does_not_query_engine(self):
        self.call('store: durable fixture fact')
        before = self.recorded()
        self.assertEqual(self.call(event='Stop'), '')
        self.assertEqual(self.recorded(), before)

    def test_malformed_spy_cannot_pass_positive_control(self):
        self.positive_control()
        self.assertEqual(self.call('ordinary input', mode='malformed'), '')
        self.assertIn('parse_error', self.log.read_text(encoding="utf-8"))


def assert_versions(root):
    version=json.loads((root/'kimi.plugin.json').read_text(encoding='utf-8'))['version']
    hook=re.search(r'^VERSION = "([^"]+)"',(root/'hooks/respire.py').read_text(encoding='utf-8'),re.M).group(1)
    if version!=hook:raise ValueError(f'kimi.plugin.json {version} != hook VERSION {hook}')

class VersionConsistency(unittest.TestCase):
    def test_actual_versions_agree(self):
        assert_versions(ROOT)

    def test_each_mismatch_is_rejected(self):
        for component in ('manifest','hook'):
            with self.subTest(component=component), tempfile.TemporaryDirectory() as directory:
                fixture=Path(directory);(fixture/'hooks').mkdir()
                shutil.copy2(ROOT/'kimi.plugin.json',fixture/'kimi.plugin.json')
                shutil.copy2(ROOT/'hooks/respire.py',fixture/'hooks/respire.py')
                version=json.loads((fixture/'kimi.plugin.json').read_text(encoding='utf-8'))['version']
                hook=fixture/'hooks/respire.py'
                hook.write_text(re.sub(r'^VERSION = "[^"]+"',f'VERSION = "{version}"',hook.read_text(encoding='utf-8'),count=1,flags=re.M),encoding='utf-8')
                assert_versions(fixture)
                if component=='hook':hook.write_text(hook.read_text(encoding='utf-8').replace(f'VERSION = "{version}"','VERSION = "999.0.0"',1),encoding='utf-8')
                else:
                    path=fixture/'kimi.plugin.json';doc=json.loads(path.read_text(encoding='utf-8'));doc['version']='999.0.0';path.write_text(json.dumps(doc),encoding='utf-8')
                with self.assertRaises(ValueError):assert_versions(fixture)


class CleanupReceipt(unittest.TestCase):
    """Extract only the reviewed cleanup function; never execute the full suite."""
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='kimi-cleanup-')
        self.addCleanup(self.temp.cleanup)
        self.case = Path(self.temp.name)
        source = (ROOT/'tests/test_hooks.sh').read_text(encoding='utf-8')
        start = source.index('probe_cleanup() {')
        end = source.index('\n}\n', start) + 3
        self.runner = self.case/'cleanup.sh'
        self.runner.write_text('#!/usr/bin/env bash\nset -u\nRSRS=/nonexistent-test-only\n' +
                               source[start:end] + '\nprobe_cleanup "$1" CI "$2"\n',
                               encoding='utf-8', newline='\n')
        self.calls = self.case/'calls.jsonl'
        spy = self.case/'spy.py'
        spy.write_text('''import json, os, sys
assert len(sys.argv) == 4 and sys.argv[1] == 'forget' and sys.argv[3] == '--json'
assert len(sys.argv[2]) == 8 and all(c in '0123456789abcdef' for c in sys.argv[2])
with open(os.environ['TEST_CALLS'], 'a', encoding='utf-8') as f:
    f.write(json.dumps(sys.argv[1:]) + '\\n')
if os.environ.get('STUB_MODE') == 'forget_fail': sys.exit(7)
print(json.dumps({'status':'ok'}))
''', encoding='utf-8')
        if os.name == 'nt':
            self.engine = self.case/'rsrs-spy.cmd'
            self.engine.write_text(f'@echo off\n"{sys.executable}" "{spy}" %*\n', encoding='utf-8')
            self.bash = str(Path(os.environ.get('ProgramFiles', 'C:/Program Files'))/'Git/bin/bash.exe')
        else:
            self.engine = self.case/'rsrs-spy'
            self.engine.write_text(f'#!{sys.executable}\n'+spy.read_text(encoding='utf-8'), encoding='utf-8')
            self.bash = shutil.which('bash')
        self.engine.chmod(0o700)
        self.assertTrue(self.bash and Path(self.bash).is_file(), 'A reviewed Bash runtime is required')
        self.env = {k:v for k,v in os.environ.items() if k.upper() in
                    {'PATH','SYSTEMROOT','WINDIR','PATHEXT','TEMP','TMP','COMSPEC'}}
        self.env.update(HOME=str(self.case/'home'), USERPROFILE=str(self.case/'home'),
                        XDG_CONFIG_HOME=str(self.case/'config'), XDG_DATA_HOME=str(self.case/'data'),
                        RESPITE_CONFIG=str(self.case/'config.json'), RESPITE_LOG=str(self.case/'log'),
                        RESPITE_NUDGE_STATE=str(self.case/'counter'), RESPITE_PENDING_NUDGE=str(self.case/'pending'),
                        KIMI_PLUGIN_DATA=str(self.case/'data'), RESPITE_DATA=str(self.case/'data'),
                        TEST_CALLS=str(self.calls), PYTHONUTF8='1', PYTHONDONTWRITEBYTECODE='1')

    def check_receipt(self, receipt, expected_rc, identifier=None, mode='ok'):
        result = subprocess.run([self.bash, str(self.runner), receipt, str(self.engine)],
                                env=dict(self.env, STUB_MODE=mode), cwd=self.case,
                                text=True, encoding='utf-8', capture_output=True, timeout=20)
        self.assertEqual(result.returncode, expected_rc, result.stdout+result.stderr)
        calls = [json.loads(line) for line in self.calls.read_text(encoding='utf-8').splitlines()] if self.calls.exists() else []
        self.assertEqual(calls, [['forget', identifier, '--json']] if identifier else [])
        if expected_rc == 2:
            self.assertIn('FAIL', result.stdout)

    def test_english_receipt_calls_only_temporary_forget(self):
        self.check_receipt('【respire · stored】Saved: fixture (deadbeef). title', 0, 'deadbeef')

    def test_chinese_ascii_receipt_calls_only_temporary_forget(self):
        self.check_receipt('已存入：fixture (cafebabe)。', 0, 'cafebabe')

    def test_actual_legacy_fullwidth_receipt_is_cleaned(self):
        # Actual production format from 4e922e18abb2879f284d043a964a2c90fede2235.
        self.check_receipt('【respire·落库】已存入：fixture（feedface）。rsrs retitle feedface --title', 0, 'feedface')

    def test_english_fullwidth_receipt_calls_only_temporary_forget(self):
        self.check_receipt('Saved: fixture（deadbeef）. title', 0, 'deadbeef')

    def test_fullwidth_receipt_missing_identifier_fails_without_calls(self):
        self.check_receipt('已存入：fixture（not-an-id）。', 2)

    def test_fullwidth_receipt_failed_forget_is_reported(self):
        self.check_receipt('已存入：fixture（feedface）。', 2, 'feedface', 'forget_fail')

    def test_missing_identifier_fails_without_calls(self):
        self.check_receipt('Saved: fixture without identifier', 2)

    def test_pending_receipt_never_forgets(self):
        self.check_receipt('【respire · store pending】nothing was written', 1)

    def test_failed_forget_is_not_reported_as_cleanup(self):
        self.check_receipt('Saved: fixture (deadbeef). title', 2, 'deadbeef', 'forget_fail')


class ProcessAuditPolicy(unittest.TestCase):
    def test_windows_none_executable_and_exact_commandline_are_allowed(self):
        expected = [r'C:\temp\space name\rsrs-spy.cmd', 'recall', 'ordinary input', '--json']
        self.assertTrue(allowed_process(None, subprocess.list2cmdline(expected), expected, True))

    def test_posix_exact_executable_and_complete_argv_are_allowed(self):
        expected = ['/tmp/rsrs-spy', 'recall', 'ordinary input', '--json']
        self.assertTrue(allowed_process(expected[0], expected, expected, False))

    def test_other_programs_arguments_and_shell_additions_are_rejected(self):
        expected = [r'C:\temp\space name\rsrs-spy.cmd', 'recall', 'ordinary input', '--json']
        encoded = subprocess.list2cmdline(expected)
        for executable, argv, windows in (
            ('cmd.exe', encoded, True),
            ('python.exe', encoded, True),
            (None, encoded + ' & echo unwanted', True),
            (None, encoded + ' extra', True),
            (None, 'cmd.exe /c ' + encoded, True),
            (None, encoded.replace('rsrs-spy.cmd', 'rsrs-spy.cmd-other'), True),
            (None, encoded, False),
            (expected[0], expected + ['extra'], False),
        ):
            with self.subTest(executable=executable, argv=argv, windows=windows):
                self.assertFalse(allowed_process(executable, argv, expected, windows))


if __name__ == '__main__':
    unittest.main(verbosity=2)
