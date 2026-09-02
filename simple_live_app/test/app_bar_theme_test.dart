import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/app_style.dart';

void main() {
  group('secondary-page app bar theme', () {
    test('light app bars retain a surface without a separator', () {
      final theme = AppStyle.lightTheme.appBarTheme;

      expect(theme.backgroundColor, const Color(0xF7FFFFFF));
      expect(theme.surfaceTintColor, Colors.transparent);
      expect(theme.elevation, 0);
      expect(theme.scrolledUnderElevation, 0);
      expect(theme.shadowColor, Colors.transparent);
      expect(theme.shape, isNull);
    });

    test('dark app bars use a matching flat surface', () {
      final theme = AppStyle.darkTheme.appBarTheme;

      expect(theme.backgroundColor, const Color(0xF714171B));
      expect(theme.surfaceTintColor, Colors.transparent);
      expect(theme.elevation, 0);
      expect(theme.scrolledUnderElevation, 0);
      expect(theme.shadowColor, Colors.transparent);
      expect(theme.shape, isNull);
    });
  });
}
