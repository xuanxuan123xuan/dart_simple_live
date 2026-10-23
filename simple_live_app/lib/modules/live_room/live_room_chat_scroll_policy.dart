import 'package:flutter/rendering.dart';

bool updateChatAutoScrollDisabled({
  required bool currentlyDisabled,
  required ScrollDirection userScrollDirection,
  required bool isNearBottom,
}) {
  if (userScrollDirection == ScrollDirection.forward) {
    return true;
  }
  if (isNearBottom) {
    return false;
  }
  return currentlyDisabled;
}
