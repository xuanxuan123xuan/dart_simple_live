import json
import unittest
from unittest.mock import Mock, patch

from release_notes import NO_CHANGES, SECTIONS, generate, render, request_summary, validate


class ReleaseNotesTest(unittest.TestCase):
    def setUp(self):
        self.value = {key: [] for key in SECTIONS}
        self.value['fixes'] = ['修复 Windows 播放画面闪烁。']

    def test_valid_chinese_and_all_headings(self):
        text = render(validate(self.value))
        self.assertEqual(text.count('### '), 4)
        self.assertEqual(text.count('- '), 4)
        self.assertIn(self.value['fixes'][0], text)

    def test_invalid_schema_and_items(self):
        for value in [None, True, [], {}, {**self.value, 'extra': []},
                      {**self.value, 'fixes': '修复播放问题'},
                      {**self.value, 'fixes': ['修复播放问题'] * 5}]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate(value)
        for item in ['Fix playback crashes', '修复播放问题 fix crashes',
                     '修复播放问题\nInjected text', '**修复播放问题**',
                     '更新仓库构建脚本', '修复播放问题,优化画面',
                     '修复播放问题😀', '修复播放问题' * 8, 123]:
            with self.subTest(item=item), self.assertRaises(ValueError):
                validate({**self.value, 'fixes': [item]})

    def test_retry_then_valid(self):
        for first in ['not JSON', json.dumps({'fixes': []}),
                      json.dumps({**self.value, 'fixes': ['Fix playback']}),
                      OSError('API unavailable')]:
            request = Mock(side_effect=[first, json.dumps(self.value)])
            self.assertIn(self.value['fixes'][0], generate('commits', 'TV', 'key', request))
            self.assertEqual(request.call_count, 2)

    def test_accepts_user_visible_technical_terms(self):
        value = {key: [] for key in SECTIONS}
        value['fixes'] = ['修复快手 Cookie 播放问题。']
        value['improvements'] = ['优化 HLS 直播链接切换。']
        value['engineering'] = ['完善 Windows 与 Android 适配。']
        validate(value)

    def test_accepts_wrapped_and_structured_response_content(self):
        value = json.dumps(self.value)
        for content in [value, f'```json\n{value}\n```',
                        [{"type": "text", "text": value}],
                        {"text": value}, json.loads(value)]:
            request = Mock(return_value=content)
            result = generate('commits', 'TV', 'key', request)
            self.assertIn(self.value['fixes'][0], result)

    def test_failure_and_missing_key_use_chinese_fallback(self):
        request = Mock(side_effect=OSError('API unavailable'))
        text = generate('English commit title', 'App', 'key', request)
        self.assertEqual(request.call_count, 2)
        self.assertEqual(text.count('### '), 4)
        self.assertEqual(text.count('- '), 4)
        self.assertNotIn('English', text)
        self.assertIn('说明暂不可用', text)
        request.reset_mock()
        self.assertEqual(generate('commits', 'TV', '', request), text)
        request.assert_not_called()

    def test_empty_changes_skip_ai_even_with_a_key(self):
        request = Mock()
        for audience in ['App', 'TV']:
            for commits in ['', ' \n\t']:
                with self.subTest(audience=audience, commits=commits):
                    text = generate(commits, audience, 'key', request)
                    self.assertIn(NO_CHANGES, text)
                    self.assertEqual(text.count('### '), 4)
                    self.assertNotIn('说明暂不可用', text)
        request.assert_not_called()

    def test_successful_summary_with_no_user_changes_is_not_an_api_failure(self):
        request = Mock(return_value={key: [] for key in SECTIONS})
        text = generate('maintenance evidence', 'TV', 'key', request)
        self.assertIn(NO_CHANGES, text)
        self.assertNotIn('说明暂不可用', text)
        request.assert_called_once()

    def test_prompt_scopes_each_client_and_uses_filtered_evidence(self):
        content = json.dumps(self.value)
        response = Mock()
        response.read.return_value = json.dumps({
            'choices': [{'message': {'content': content}}],
        }).encode()
        context = Mock()
        context.__enter__ = Mock(return_value=response)
        context.__exit__ = Mock(return_value=False)
        evidence = '[{"files": ["scoped/path.dart"], "patch": "scoped evidence"}]'
        for audience, target in [('App', '普通版，面向手机和桌面平台'),
                                 ('TV', 'TV 版，面向 Android TV 与 Windows TV')]:
            with self.subTest(audience=audience), patch(
                'release_notes.urllib.request.urlopen', return_value=context,
            ) as urlopen:
                self.assertEqual(request_summary(evidence, audience, 'fake-key'), content)
                body = json.loads(urlopen.call_args.args[0].data)
                prompt, data = body['messages']
                self.assertIn(target, prompt['content'])
                self.assertIn('不能作为该端功能已实现的证据', prompt['content'])
                self.assertIn('只根据提供的文件与差异', prompt['content'])
                self.assertIn('跨端同步', prompt['content'])
                self.assertEqual(data, {'role': 'user', 'content': evidence})


if __name__ == '__main__':
    unittest.main()
