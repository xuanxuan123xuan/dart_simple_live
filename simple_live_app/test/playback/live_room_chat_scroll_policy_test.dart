import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/live_room_chat_scroll_policy.dart';

void main() {
  test('upward scroll pauses auto-follow even within the bottom threshold', () {
    expect(
      updateChatAutoScrollDisabled(
        currentlyDisabled: false,
        userScrollDirection: ScrollDirection.forward,
        isNearBottom: true,
      ),
      isTrue,
    );
  });

  test('auto-follow stays paused while new messages arrive away from bottom', () {
    var disabled = updateChatAutoScrollDisabled(
      currentlyDisabled: false,
      userScrollDirection: ScrollDirection.forward,
      isNearBottom: true,
    );

    for (var i = 0; i < 3; i++) {
      disabled = updateChatAutoScrollDisabled(
        currentlyDisabled: disabled,
        userScrollDirection: ScrollDirection.idle,
        isNearBottom: false,
      );
    }

    expect(disabled, isTrue);
  });

  test('scrolling back near bottom restores auto-follow', () {
    expect(
      updateChatAutoScrollDisabled(
        currentlyDisabled: true,
        userScrollDirection: ScrollDirection.reverse,
        isNearBottom: true,
      ),
      isFalse,
    );
  });

  test('moving away from bottom without upward intent preserves current state', () {
    expect(
      updateChatAutoScrollDisabled(
        currentlyDisabled: false,
        userScrollDirection: ScrollDirection.idle,
        isNearBottom: false,
      ),
      isFalse,
    );
  });
}
