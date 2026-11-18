import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:simple_live_app/app/mobile_safe_insets.dart';

void main() {
  const base = MediaQueryData(
    padding: EdgeInsets.only(top: 24, bottom: 12),
    viewPadding: EdgeInsets.only(top: 24, bottom: 12),
  );

  test('clamps mobile extra insets and preserves physical padding', () {
    final result = mobilePageMediaQuery(
      base,
      topExtra: 100,
      bottomExtra: -4,
      isMobile: true,
    );
    expect(result.padding.top, 104);
    expect(result.padding.bottom, 12);
    expect(result.viewPadding, base.viewPadding);
  });

  test('does not add bottom space while the keyboard is visible', () {
    final result = mobilePageMediaQuery(
      base.copyWith(viewInsets: const EdgeInsets.only(bottom: 300)),
      topExtra: 8,
      bottomExtra: 40,
      isMobile: true,
    );
    expect(result.padding.top, 32);
    expect(result.padding.bottom, 12);
  });

  test('desktop and disabled paths return the original media query', () {
    expect(
      identical(
        mobilePageMediaQuery(base, topExtra: 20, bottomExtra: 20, isMobile: false),
        base,
      ),
      isTrue,
    );
    expect(
      identical(
        mobilePageMediaQuery(
          base,
          topExtra: 20,
          bottomExtra: 20,
          isMobile: true,
          enabled: false,
        ),
        base,
      ),
      isTrue,
    );
  });

  test('iOS bottom action inset keeps a compact portrait baseline', () {
    expect(mobileBottomActionInset(base, isIOS: true), 12);
    expect(
      mobileBottomActionInset(
        base.copyWith(
          padding: const EdgeInsets.only(bottom: 52),
          viewPadding: const EdgeInsets.only(bottom: 34),
        ),
        isIOS: true,
      ),
      34,
    );
  });
}
