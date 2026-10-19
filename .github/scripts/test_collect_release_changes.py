"""Offline integration tests for product-scoped release evidence."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock

from collect_release_changes import collect_changes, previous_release_tag
from release_notes import NO_CHANGES, SECTIONS, generate


class CollectReleaseChangesTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.repo = Path(self.directory.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Release Test')
        self.git('config', 'user.email', 'release-test@example.invalid')
        self.git('config', 'commit.gpgsign', 'false')
        self.git('config', 'tag.gpgsign', 'false')
        self.git('config', 'core.autocrlf', 'false')

    def git(self, *args, input=None):
        return subprocess.run(
            ['git', '-C', str(self.repo), *args], input=input,
            check=True, capture_output=True, encoding='utf-8',
        ).stdout.strip()

    def commit(self, files, subject='Update playback'):
        for name, content in files.items():
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding='utf-8')
        self.git('add', '--all')
        self.git('commit', '-q', '-m', subject)
        return self.git('rev-parse', 'HEAD')

    def baseline(self):
        self.commit({'README.md': 'initial\n'}, 'Initial maintenance')
        self.git('tag', 'v1.0.0')
        self.git('tag', 'tv_v1.0.0')

    def records(self, audience, tag='', **kwargs):
        result = collect_changes(self.repo, audience, tag, **kwargs)
        return json.loads(result) if result else []

    def test_product_paths_override_misleading_subjects(self):
        self.baseline()
        app = self.commit({'simple_live_app/lib/player.dart': 'app only\n'},
                          'TV remote playback fix')
        tv = self.commit({'simple_live_tv_app/lib/player.dart': 'tv only\n'},
                         'App mobile playback fix')
        self.assertEqual([r['commit'] for r in self.records('App')], [app])
        self.assertEqual([r['commit'] for r in self.records('TV')], [tv])

    def test_shared_and_platform_specific_dependency_paths(self):
        self.baseline()
        shared = {
            'simple_live_core/lib/provider.dart',
            'third_party/canvas_danmaku/lib/screen.dart',
            'third_party/media_kit_video/lib/player.dart',
            'third_party/media_kit_video/android/src/Player.java',
            'third_party/media_kit_video/windows/player.cpp',
            'simple_live_app/third_party/flutter_inappwebview_android/lib/plugin.dart',
        }
        app_only = {
            'third_party/dart_quickjs_compat/lib/quickjs.dart',
            'third_party/media_kit_video/ios/Classes/Player.swift',
            'third_party/media_kit_video/macos/Classes/Player.swift',
            'third_party/media_kit_video/linux/player.cc',
        }
        self.commit({path: f'implementation for {path}\n' for path in shared | app_only})
        self.assertEqual(set(self.records('App')[0]['files']), shared | app_only)
        self.assertEqual(set(self.records('TV')[0]['files']), shared)

    def test_mixed_commit_filters_both_file_list_and_patch(self):
        self.baseline()
        paths = {
            'simple_live_app/lib/mobile.dart': 'APP_ONLY_SECRET_MARKER\n',
            'simple_live_tv_app/lib/remote.dart': 'TV_ONLY_SECRET_MARKER\n',
            'simple_live_core/lib/player.dart': 'SHARED_PLAYBACK_MARKER\n',
            'docs/release.md': 'UNRELATED_DOC_MARKER\n',
        }
        commit = self.commit(paths, 'App mobile and TV remote improvements')
        for audience, own_path, own_marker, other_marker in (
            ('App', 'simple_live_app/lib/mobile.dart', 'APP_ONLY_SECRET_MARKER',
             'TV_ONLY_SECRET_MARKER'),
            ('TV', 'simple_live_tv_app/lib/remote.dart', 'TV_ONLY_SECRET_MARKER',
             'APP_ONLY_SECRET_MARKER'),
        ):
            with self.subTest(audience=audience):
                records = self.records(audience)
                self.assertEqual(len(records), 1)
                self.assertEqual(records[0]['commit'], commit)
                self.assertEqual(set(records[0]['files']),
                                 {own_path, 'simple_live_core/lib/player.dart'})
                self.assertIn(own_marker, records[0]['patch'])
                self.assertIn('SHARED_PLAYBACK_MARKER', records[0]['patch'])
                self.assertNotIn(other_marker, records[0]['patch'])
                self.assertNotIn('UNRELATED_DOC_MARKER', records[0]['patch'])
                self.assertFalse(records[0]['patch_truncated'])

    def test_maintenance_and_version_only_changes_are_excluded(self):
        self.commit({
            'simple_live_app/pubspec.yaml': 'name: client\nversion: 1.0.0\n',
            'simple_live_tv_app/pubspec.yaml': 'name: tv\nversion: 1.0.0\n',
            'simple_live_app/ohos/AppScope/app.json5':
                '{\n  "versionCode": 100,\n  "versionName": "1.0.0"\n}\n',
        })
        self.git('tag', 'v1.0.0')
        self.git('tag', 'tv_v1.0.0')
        self.commit({
            'simple_live_app/pubspec.yaml': 'name: client\nversion: 1.0.1\n',
            'simple_live_tv_app/pubspec.yaml': 'name: tv\nversion: 1.0.1\n',
            'simple_live_app/lib/generated/app_version.g.dart': 'version = "1.0.1";\n',
            'simple_live_app/lib/generated/app_update_channel.g.dart': 'channel = "dev";\n',
            'simple_live_app/ohos/AppScope/app.json5':
                '{\n  "versionCode": 101,\n  "versionName": "1.0.1"\n}\n',
            'simple_live_core/test/player_test.dart': 'test change\n',
            'simple_live_tv_app/test/remote_test.dart': 'test change\n',
            'simple_live_app/docs/guide.txt': 'documentation\n',
            'simple_live_tv_app/README.md': 'documentation\n',
            'third_party/media_kit_video/example/lib/main.dart': 'example\n',
        }, 'Release version and maintenance')
        for audience in ('App', 'TV'):
            with self.subTest(audience=audience):
                self.assertEqual(collect_changes(self.repo, audience, ''), '')

    def test_manifest_behavior_change_is_retained_alongside_version_bump(self):
        manifest = 'simple_live_app/ohos/AppScope/app.json5'
        self.commit({manifest:
                     '{\n  "versionCode": 100,\n  "versionName": "1.0.0",\n'
                     '  "icon": "$media:old_icon"\n}\n'})
        self.git('tag', 'v1.0.0')
        commit = self.commit({manifest:
                              '{\n  "versionCode": 101,\n  "versionName": "1.0.1",\n'
                              '  "icon": "$media:new_icon"\n}\n'})
        record = self.records('App')[0]
        self.assertEqual(record['commit'], commit)
        self.assertEqual(record['files'], [manifest])
        self.assertIn('+  "icon": "$media:new_icon"', record['patch'])

    def test_pubspec_dependency_changes_remain_in_evidence(self):
        self.commit({'simple_live_core/pubspec.yaml':
                     'name: core\nversion: 1.0.0\ndependencies:\n  player: 1.0.0\n'})
        self.git('tag', 'v1.0.0')
        self.git('tag', 'tv_v1.0.0')
        commit = self.commit({'simple_live_core/pubspec.yaml':
                              'name: core\nversion: 1.0.1\ndependencies:\n  player: 2.0.0\n'})
        for audience in ('App', 'TV'):
            with self.subTest(audience=audience):
                record = self.records(audience)[0]
                self.assertEqual(record['commit'], commit)
                self.assertEqual(record['files'], ['simple_live_core/pubspec.yaml'])
                self.assertIn('+  player: 2.0.0', record['patch'])

    def test_first_release_includes_root_commit(self):
        root = self.commit({'simple_live_core/lib/player.dart': 'root playback\n'})
        for audience in ('App', 'TV'):
            with self.subTest(audience=audience):
                records = self.records(audience)
                self.assertEqual([r['commit'] for r in records], [root])
                self.assertIn('+root playback', records[0]['patch'])

    def test_empty_range_does_not_fall_back_to_old_history(self):
        self.commit({'simple_live_core/lib/player.dart': 'already released\n'})
        self.git('tag', 'v1.0.0')
        self.git('tag', 'tv_v1.0.0')
        self.commit({'README.md': 'maintenance since last release\n'})
        self.assertEqual(collect_changes(self.repo, 'App', 'v1.1.0'), '')
        self.assertEqual(collect_changes(self.repo, 'TV', 'tv_v1.1.0'), '')

    def test_release_tags_are_isolated_by_product_channel_and_reachability(self):
        self.baseline()
        for name in ('v1.1.0', 'tv_v1.2.0', 'v1.3.0-dev', 'tv_v1.4.0-dev',
                     'v1.5.0-pre', 'tv_v1.6.0-pre', 'v8.0.0-beta',
                     'tv_v8.0.0-beta'):
            self.git('tag', name)
        self.commit({'simple_live_core/lib/player.dart': 'current playback\n'})
        # Current release tags already point at HEAD during release workflows.
        for name in ('v2.0.0', 'tv_v2.0.0', 'v2.0.0-dev', 'tv_v2.0.0-dev',
                     'v2.0.0-pre', 'tv_v2.0.0-pre'):
            self.git('tag', name)
        tree = self.git('rev-parse', 'HEAD^{tree}')
        unreachable = self.git('commit-tree', tree, input='Unreachable release\n')
        for name in ('v99.0.0', 'tv_v99.0.0', 'v99.0.0-dev',
                     'tv_v99.0.0-dev', 'v99.0.0-pre', 'tv_v99.0.0-pre'):
            self.git('tag', name, unreachable)
        cases = (
            ('App', 'v2.0.0', '', False, 'v1.1.0'),
            ('TV', 'tv_v2.0.0', '', False, 'tv_v1.2.0'),
            ('App', 'v2.0.0-dev', 'dev', False, 'v1.3.0-dev'),
            ('TV', 'tv_v2.0.0-dev', 'dev', True, 'tv_v1.4.0-dev'),
            ('App', 'v2.0.0-pre', 'main', True, 'v1.5.0-pre'),
            ('TV', 'tv_v2.0.0-pre', 'main', True, 'tv_v1.6.0-pre'),
        )
        for audience, tag, branch, prerelease, expected in cases:
            with self.subTest(audience=audience, branch=branch, prerelease=prerelease):
                self.assertEqual(previous_release_tag(
                    self.repo, audience, tag, branch, prerelease), expected)

    def test_many_other_product_commits_do_not_crowd_out_shared_changes(self):
        self.baseline()
        shared = self.commit({'simple_live_core/lib/player.dart': 'relevant playback\n'})
        # Reuse two trees to build real alternating TV changes cheaply.
        self.commit({'simple_live_tv_app/lib/remote.dart': 'first\n'})
        tree_a = self.git('rev-parse', 'HEAD^{tree}')
        self.commit({'simple_live_tv_app/lib/remote.dart': 'second\n'})
        tree_b = self.git('rev-parse', 'HEAD^{tree}')
        parent = self.git('rev-parse', 'HEAD')
        for number in range(85):
            parent = self.git('commit-tree', tree_a if number % 2 == 0 else tree_b,
                              '-p', parent, input=f'TV remote change {number}\n')
        self.git('reset', '--hard', parent)
        self.assertEqual([r['commit'] for r in self.records('App')], [shared])
        self.git('tag', '-d', 'v1.0.0', 'tv_v1.0.0')
        self.assertEqual([r['commit'] for r in self.records('App')], [shared])

    def test_generate_receives_only_collected_product_evidence(self):
        self.baseline()
        self.commit({
            'simple_live_app/lib/mobile.dart': 'MOBILE_EVIDENCE\n',
            'simple_live_tv_app/lib/remote.dart': 'REMOTE_EVIDENCE\n',
        }, 'Combined client update')
        value = {key: [] for key in SECTIONS}
        value['fixes'] = ['修复播放切换问题。']
        for audience, own, other in (
            ('App', 'MOBILE_EVIDENCE', 'REMOTE_EVIDENCE'),
            ('TV', 'REMOTE_EVIDENCE', 'MOBILE_EVIDENCE'),
        ):
            with self.subTest(audience=audience):
                evidence = collect_changes(self.repo, audience, '')
                request = Mock(return_value=value)
                self.assertIn(value['fixes'][0], generate(evidence, audience, 'test-key',
                                                        request=request))
                request.assert_called_once_with(evidence, audience, 'test-key')
                self.assertIn(own, request.call_args.args[0])
                self.assertNotIn(other, request.call_args.args[0])
        self.git('tag', 'tv_v1.1.0')
        request = Mock()
        evidence = collect_changes(self.repo, 'TV', 'tv_v1.2.0')
        self.assertEqual(evidence, '')
        self.assertIn(NO_CHANGES, generate(evidence, 'TV', 'test-key', request=request))
        request.assert_not_called()

    def test_cli_repo_collection_without_key_returns_chinese_fallback(self):
        self.baseline()
        self.commit({'simple_live_app/lib/player.dart': 'playback change\n'})
        env = os.environ.copy()
        env.pop('DEEPSEEK_API_KEY', None)
        env['PYTHONIOENCODING'] = 'utf-8'
        script = Path(__file__).with_name('release_notes.py')
        for audience, expected in (('App', '说明暂不可用'), ('TV', NO_CHANGES)):
            with self.subTest(audience=audience):
                result = subprocess.run(
                    [sys.executable, '-B', str(script), audience, '--repo', str(self.repo),
                     '--tag', 'v1.1.0' if audience == 'App' else 'tv_v1.1.0'],
                    env=env, check=True, capture_output=True, encoding='utf-8',
                )
                self.assertIn(expected, result.stdout)
                self.assertEqual(result.stdout.count('### '), 4)
                self.assertEqual(result.stderr, '')

    def test_cli_git_failure_is_not_reported_as_empty_changes_or_fallback(self):
        env = os.environ.copy()
        env.pop('DEEPSEEK_API_KEY', None)
        env['PYTHONIOENCODING'] = 'utf-8'
        result = subprocess.run(
            [sys.executable, '-B', str(Path(__file__).with_name('release_notes.py')),
             'App', '--repo', str(self.repo / 'missing-repository')],
            env=env, capture_output=True, encoding='utf-8',
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        self.assertNotIn(NO_CHANGES, result.stdout + result.stderr)
        self.assertNotIn('说明暂不可用', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
