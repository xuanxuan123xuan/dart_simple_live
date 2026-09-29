import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

/// 抖音首页 categoryData 的真实形状（三级）：一级「游戏」→ 二级「射击游戏」
/// → 三级「绝地求生」。这里按抓取到的字段结构缩简。
Map<String, dynamic> _partition(String idStr, int type, String title) => {
      'id_str': idStr,
      'type': type,
      'title': title,
    };

void main() {
  group('LiveSubCategory 多级嵌套', () {
    test('三级 JSON 逐级嵌套且 parentId 指向父 id', () {
      final json = {
        'id': '103,4',
        'name': '游戏',
        'parentId': '103,4',
        'pic': null,
        'children': [
          {
            'id': '1,1',
            'name': '射击游戏',
            'parentId': '103,4',
            'pic': null,
            'children': [
              {
                'id': '1010026,1',
                'name': '绝地求生',
                'parentId': '1,1',
                'pic': null,
                'children': [],
              },
              {
                'id': '1010003,1',
                'name': 'CSGO',
                'parentId': '1,1',
                'pic': null,
                'children': [],
              },
            ],
          },
        ],
      };

      final level1 = LiveSubCategory.fromJson(json);

      expect(level1.hasChildren, isTrue);
      expect(level1.children, hasLength(1));

      final level2 = level1.children.first;
      expect(level2.name, '射击游戏');
      expect(level2.parentId, level1.id);
      expect(level2.hasChildren, isTrue);
      expect(level2.children, hasLength(2));

      final level3 = level2.children.first;
      expect(level3.name, '绝地求生');
      expect(level3.parentId, level2.id);
      expect(level3.hasChildren, isFalse);
      expect(level3.children, isEmpty);
    });

    test('JSON 往返后多级 children 不丢失', () {
      final json = {
        'id': '103,4',
        'name': '游戏',
        'parentId': '103,4',
        'pic': 'https://example.com/a.png',
        'children': [
          {
            'id': '1,1',
            'name': '射击游戏',
            'parentId': '103,4',
            'pic': null,
            'children': [
              {
                'id': '1010026,1',
                'name': '绝地求生',
                'parentId': '1,1',
                'pic': null,
                'children': [],
              },
            ],
          },
        ],
      };

      final first = LiveSubCategory.fromJson(json);
      final encoded = jsonEncode(first.toJson());
      final second = LiveSubCategory.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );

      expect(jsonEncode(second.toJson()), encoded);
      expect(second.children.first.children.first.name, '绝地求生');
    });

    test('LiveCategory 快照保留子分类的嵌套', () {
      final category = LiveCategory.fromJson({
        'id': '103,4',
        'name': '游戏',
        'pic': 'https://example.com/game.png',
        'children': [
          {
            'id': '1,1',
            'name': '射击游戏',
            'parentId': '103,4',
            'pic': null,
            'children': [
              {
                'id': '1010026,1',
                'name': '绝地求生',
                'parentId': '1,1',
                'pic': null,
                'children': [],
              },
            ],
          },
        ],
      });

      expect(category.pic, 'https://example.com/game.png');
      expect(category.children, hasLength(1));
      expect(category.children.first.children.first.name, '绝地求生');
    });
  });

  group('异常数据不应让整份快照解析失败', () {
    test('children 为 null / 非 List 时按空处理', () {
      for (final value in [null, 'x', 42, <dynamic>[]]) {
        final sub = LiveSubCategory.fromJson({
          'id': '1,4',
          'name': '聊天',
          'parentId': '1,4',
          'children': value,
        });
        expect(sub.children, isEmpty, reason: 'value=$value');
        expect(sub.hasChildren, isFalse);
      }
    });

    test('children 中的非 Map 元素被跳过，合法兄弟保留', () {
      final sub = LiveSubCategory.fromJson({
        'id': '1,4',
        'name': '聊天',
        'parentId': '1,4',
        'children': [
          'oops',
          123,
          null,
          {
            'id': '2,4',
            'name': '音乐',
            'parentId': '1,4',
            'children': [],
          },
        ],
      });

      expect(sub.children, hasLength(1));
      expect(sub.children.single.name, '音乐');
    });

    test('子节点缺 id/name/parentId 时被跳过，其余保留', () {
      final sub = LiveSubCategory.fromJson({
        'id': '1,4',
        'name': '聊天',
        'parentId': '1,4',
        'children': [
          {'name': '缺 id', 'parentId': '1,4', 'children': []},
          {'id': '2,4', 'parentId': '1,4', 'children': []},
          {'id': '3,4', 'name': '缺 parentId', 'children': []},
          {
            'id': '4,4',
            'name': '合法',
            'parentId': '1,4',
            'children': [],
          },
        ],
      });

      expect(sub.children.map((e) => e.name), ['合法']);
    });

    test('空 title 与异常 partition 由调用方跳过（模型层只认显式字段）', () {
      // 模型要求 id/name/parentId 显式存在；抖音侧 _parseSubCategory 负责
      // 把空标题、非 Map 的 partition 过滤成 null。这里验证模型层不会因为
      // 多余字段或空字符串而抛异常。
      final sub = LiveSubCategory.fromJson({
        'id': '101,4',
        'name': '   ',
        'parentId': '101,4',
        'partition': {},
        'sub_partition': null,
      });
      expect(sub.name, '   ');
      expect(sub.children, isEmpty);
    });

    test('顶层 LiveCategory 缺字段时抛 FormatException', () {
      expect(
        () => LiveCategory.fromJson({'name': '游戏'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => LiveCategory.fromJson({'id': '1', 'name': 'x'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('旧快照兼容', () {
    test('没有 children 字段的两级旧数据解析为无子分类', () {
      final sub = LiveSubCategory.fromJson({
        'name': '射击游戏',
        'id': '1,1',
        'parentId': '103,4',
        'pic': null,
      });

      expect(sub.children, isEmpty);
      expect(sub.hasChildren, isFalse);
      expect(sub.toJson()['children'], isEmpty);
    });

    test('toJson 始终输出 children 键，便于旧版消费方安全读取', () {
      final sub = LiveSubCategory.fromJson({
        'name': '聊天',
        'id': '101,4',
        'parentId': '101,4',
      });

      final json = sub.toJson();
      expect(json.containsKey('children'), isTrue);
      expect(json['children'], isA<List<dynamic>>());
      expect(json['name'], '聊天');
      expect(json['id'], '101,4');
      expect(json['parentId'], '101,4');
    });
  });

  test('异常顶层 sub_partition 不会阻止其余分类解析', () async {
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response<String>(
            requestOptions: options,
            statusCode: 200,
            data:
                r'''<script>\"categoryData\":[{"partition":{"id_str":"1","type":4,"title":"游戏"},"sub_partition":null},{"partition":{"id_str":"2","type":4,"title":"聊天"},"sub_partition":"invalid"},null]</script>''',
          ),
        );
      },
    );
    HttpClient.instance.dio.interceptors.add(interceptor);
    addTearDown(() => HttpClient.instance.dio.interceptors.remove(interceptor));

    final categories = await DouyinSite().getCategores();

    expect(categories.map((item) => item.name), ['游戏', '聊天']);
    expect(categories.every((item) => item.children.length == 1), isTrue);
  });
}
