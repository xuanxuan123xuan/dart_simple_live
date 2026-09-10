import json
import unittest
from unittest.mock import Mock

from release_notes import SECTIONS, generate, render, validate


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


if __name__ == '__main__':
    unittest.main()
