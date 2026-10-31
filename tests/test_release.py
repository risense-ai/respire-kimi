"""Offline release-policy tests; all network/gh mutations are excluded."""
import importlib.util
import io
import json
import os
from pathlib import Path
from unittest import mock
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('release', Path(__file__).resolve().parents[1] / 'scripts/release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
SHA = '6c1bd2224fa343a684aea481ddff800910fa80f7'


def package(version='0.1.1', comment=SHA, extra=None):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w') as archive:
        archive.comment = comment.encode()
        archive.writestr('kimi.plugin.json', json.dumps({'name':'respire','version':version}))
        archive.writestr('hooks/respire.py', 'VERSION = "' + version + '"\n')
        for name in ('SYSTEM.md','README.md','LICENSE','skills/respire/SKILL.md','commands/recall.md','commands/store.md','commands/sync.md'):
            archive.writestr(name, '{}')
        if extra:
            # ZipInfo's constructor normalizes backslashes on Windows. Set the
            # raw archive name afterwards so this remains a genuinely unsafe
            # fixture on every OS instead of silently becoming a safe path.
            member = zipfile.ZipInfo('fixture')
            member.filename = extra
            archive.writestr(member, '')
    return buffer.getvalue()


class ReleasePolicy(unittest.TestCase):
    def test_valid_exact_archive(self):
        release.verify_zip(package(), 'v0.1.1', SHA)

    def test_wrong_version_or_commit_is_rejected(self):
        for data in (package('0.1.0'), package(comment='a' * 40)):
            with self.assertRaises(ValueError):
                release.verify_zip(data, 'v0.1.1', SHA)

    def test_unsafe_archive_is_rejected(self):
        for name in ('../escape', '/absolute', 'hooks\\escape', 'hooks/hook.log', 'hooks/__pycache__/x'):
            with self.subTest(name=name):
                data = package(extra=name)
                self.assertIn(name.encode(), data)
                with zipfile.ZipFile(io.BytesIO(data)) as archive:
                    self.assertIn(name, [member.orig_filename for member in archive.infolist()])
                with self.assertRaises(ValueError):
                    release.verify_zip(data, 'v0.1.1', SHA)

    def test_input_injection_and_noncanonical_tags_are_rejected(self):
        for tag in ('main', 'v01.4.1', 'v0.1.1;echo bad', 'v0.1.1\nsha=bad'):
            with self.assertRaises(ValueError):
                release.validate_identity(tag, SHA)

    def test_identical_assets_are_idempotent(self):
        existing = {'body': 'Source commit: ' + SHA,
                    'assets': [{'name': 'package.zip', 'digest': 'sha256:abc'}]}
        self.assertEqual(release.asset_plan(existing, {'package.zip':'abc'}, SHA), [])
        self.assertEqual(release.asset_plan(existing, {'package.zip':'abc', 'SHA256SUMS':'def'}, SHA), ['SHA256SUMS'])

    def test_conflicting_or_unknown_assets_never_overwrite(self):
        for existing in (
            {'body': '', 'assets': []},
            {'body': 'Source commit: ' + SHA, 'assets': [{'name':'package.zip','digest':'sha256:wrong'}]},
            {'body': 'Source commit: ' + SHA, 'assets': [{'name':'unexpected','digest':'sha256:abc'}]},
        ):
            with self.assertRaises(ValueError):
                release.asset_plan(existing, {'package.zip':'abc'}, SHA)

    def test_recovery_rejects_nonmain_and_wrong_repository_before_fetch(self):
        for repo, ref in ((release.REPO, 'refs/heads/feature'), ('fork/respire-kimi', 'refs/heads/main')):
            env = {'GITHUB_EVENT_NAME':'workflow_dispatch', 'GITHUB_REF':ref,
                   'GITHUB_REPOSITORY':repo, 'RELEASE_TAG':'v0.1.1', 'EXPECTED_SHA':SHA}
            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(release, 'command') as command:
                with self.assertRaises(ValueError):
                    release.resolve_source()
                command.assert_not_called()

    def test_pr_cannot_enter_publisher(self):
        with mock.patch.dict(os.environ, {'GITHUB_REPOSITORY':release.REPO,
                                        'GITHUB_EVENT_NAME':'pull_request','GITHUB_REF':'refs/pull/3/merge'}, clear=True):
            with self.assertRaises(ValueError):
                release.publish()

    def test_recovery_fetches_exact_tag_and_rejects_changed_sha(self):
        env = {'GITHUB_REPOSITORY':release.REPO, 'GITHUB_EVENT_NAME':'workflow_dispatch',
               'GITHUB_REF':'refs/heads/main', 'RELEASE_TAG':'v0.1.1', 'EXPECTED_SHA':SHA}
        with mock.patch.dict(os.environ, env, clear=True), \
                mock.patch.object(release, 'command', side_effect=['', 'a' * 40]) as command, \
                mock.patch.object(release.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'Remote tag changed'):
                release.resolve_source()
            self.assertEqual(command.call_args_list[0].args,
                             ('git','fetch','--no-tags','origin','refs/tags/v0.1.1'))
            run.assert_not_called()

    def test_creation_response_identifies_draft_without_list_readback(self):
        draft = {'id':123, 'tag_name':'v0.1.1', 'draft':True, 'body':'Source commit: '+SHA}
        with mock.patch.object(release, 'command', return_value=json.dumps(draft)) as command:
            self.assertEqual(release.create_draft('v0.1.1', SHA, draft['body']), draft)
            self.assertEqual(command.call_count, 1)
            self.assertIn('POST', command.call_args.args)
        with mock.patch.object(release, 'command', return_value='{}'):
            with self.assertRaises(ValueError):
                release.create_draft('v0.1.1', SHA, draft['body'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
