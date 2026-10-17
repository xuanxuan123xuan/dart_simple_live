import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';

void main() {
  final tags = [
    FollowUserTag(id: 'builtin', tag: '全部', userId: const []),
    FollowUserTag(id: 'custom', tag: '游戏', userId: const []),
  ];

  test('tag names are trimmed and limited to eight characters', () {
    expect(normalizeFollowUserTagName('  游戏  '), '游戏');
    expect(normalizeFollowUserTagName(''), isNull);
    expect(normalizeFollowUserTagName('   '), isNull);
    expect(normalizeFollowUserTagName('12345678'), '12345678');
    expect(normalizeFollowUserTagName('123456789'), isNull);
  });

  test('adding a tag rejects names already used by built-in or custom tags', () {
    expect(
      hasDuplicateFollowUserTagName(
        normalizeFollowUserTagName(' 游戏 ')!,
        tags,
      ),
      isTrue,
    );
    expect(
      hasDuplicateFollowUserTagName(
        normalizeFollowUserTagName('新标签')!,
        tags,
      ),
      isFalse,
    );
  });

  test('renaming a tag ignores the tag being edited', () {
    expect(
      hasDuplicateFollowUserTagName(
        '游戏',
        tags,
        ignoreId: 'custom',
      ),
      isFalse,
    );
    expect(
      hasDuplicateFollowUserTagName(
        '全部',
        tags,
        ignoreId: 'custom',
      ),
      isTrue,
    );
  });
}
