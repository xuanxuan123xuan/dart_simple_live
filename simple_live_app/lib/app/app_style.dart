import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class AppColors {
  static ColorScheme lightColorScheme = ColorScheme.fromSeed(
    // primarySwatch: Colors.blue,
    seedColor: const Color(0xff3498db),
    brightness: Brightness.light,
  );
  static ColorScheme darkColorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff3498db),
    brightness: Brightness.dark,
  );

  /// 按 seed 缓存 light/dark ColorScheme：主题切换（深色/浅色/跟随系统）
  /// 与动态取色开关变化时 seed 未变，直接复用缓存，不再每次 rebuild 重算
  /// ColorScheme.fromSeed（鸿蒙上该计算 + 全局重建叠加会明显卡顿）。
  static final Map<int, ({ColorScheme light, ColorScheme dark})> _schemeCache =
      {};
  static ({ColorScheme light, ColorScheme dark}) cachedSchemes(Color seed) {
    return _schemeCache.putIfAbsent(
      seed.toARGB32(),
      () => (
        light: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        dark: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
      ),
    );
  }

  static const Color black333 = Color(0xFF333333);
}

class AppStyle {
  static ThemeData lightTheme = ThemeData(
    colorScheme: AppColors.lightColorScheme,
    useMaterial3: true,
    fontFamily: Platform.isWindows ? "Microsoft YaHei" : null,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      centerTitle: true,
      // Standard secondary-page app bars keep an opaque-enough surface, but
      // stay flat so they do not draw a separator below every page title.
      backgroundColor: const Color(0xF7FFFFFF),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      titleTextStyle: const TextStyle(
        fontSize: 16,
        color: AppColors.black333,
      ),
      foregroundColor: AppColors.black333,
      systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
        systemNavigationBarColor: Colors.transparent,
      ),
    ),
    dialogTheme: const DialogThemeData(
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      modalElevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    drawerTheme: const DrawerThemeData(
      surfaceTintColor: Colors.transparent,
      elevation: 12,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: Color(0xB8F8FAFF),
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),

    // radioTheme: RadioThemeData(
    //   fillColor: MaterialStateProperty.all(AppColors.lightColorScheme.primary),
    // ),
    // checkboxTheme: CheckboxThemeData(
    //   fillColor: MaterialStateProperty.all(AppColors.lightColorScheme.primary),
    // ),
    // tabBarTheme: TabBarTheme(
    //   labelColor: AppColors.lightColorScheme.primary,
    //   unselectedLabelColor: Colors.white70,
    //   indicatorSize: TabBarIndicatorSize.tab,
    //   indicator: RectangularIndicator(
    //     color: Colors.white.withOpacity(.8),
    //     topLeftRadius: 24,
    //     bottomLeftRadius: 24,
    //     topRightRadius: 24,
    //     bottomRightRadius: 24,
    //     verticalPadding: 8,
    //     horizontalPadding: 0,
    //   ),
    // ),
  );

  static ThemeData darkTheme = ThemeData.dark().copyWith(
    colorScheme: AppColors.darkColorScheme,
    visualDensity: VisualDensity.standard,
    textTheme: ThemeData.dark().textTheme.apply(
          fontFamily: Platform.isWindows ? "Microsoft YaHei" : null,
        ),
    primaryTextTheme: ThemeData().textTheme.apply(
          fontFamily: Platform.isWindows ? "Microsoft YaHei" : null,
        ),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: const Color(0xF714171B),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      titleTextStyle: const TextStyle(
        fontSize: 16,
        color: Colors.white,
      ),
      foregroundColor: Colors.white,
      systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
        systemNavigationBarColor: Colors.transparent,
      ),
    ),
    dialogTheme: const DialogThemeData(
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      modalElevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    drawerTheme: const DrawerThemeData(
      surfaceTintColor: Colors.transparent,
      elevation: 12,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: Color(0xC414171B),
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
    // radioTheme: RadioThemeData(
    //   fillColor: MaterialStateProperty.all(AppColors.darkColorScheme.primary),
    // ),
    // checkboxTheme: CheckboxThemeData(
    //   fillColor: MaterialStateProperty.all(AppColors.darkColorScheme.primary),
    // ),
    // tabBarTheme: TabBarTheme(
    //   labelColor: AppColors.darkColorScheme.primary,
    //   unselectedLabelColor: Colors.white70,
    //   indicator: RectangularIndicator(
    //     color: Colors.white.withAlpha(50),
    //     topLeftRadius: 24,
    //     bottomLeftRadius: 24,
    //     topRightRadius: 24,
    //     bottomRightRadius: 24,
    //     verticalPadding: 8,
    //     horizontalPadding: 0,
    //   ),
    // ),
  );
  static const vGap4 = SizedBox(
    height: 4,
  );
  static const vGap8 = SizedBox(
    height: 8,
  );
  static const vGap12 = SizedBox(
    height: 12,
  );
  static const vGap24 = SizedBox(
    height: 24,
  );
  static const vGap32 = SizedBox(
    height: 32,
  );
  static const vGap48 = SizedBox(
    height: 48,
  );

  static const hGap4 = SizedBox(
    width: 4,
  );
  static const hGap8 = SizedBox(
    width: 8,
  );
  static const hGap12 = SizedBox(
    width: 12,
  );
  static const hGap16 = SizedBox(
    width: 16,
  );

  static const hGap24 = SizedBox(
    width: 24,
  );
  static const hGap32 = SizedBox(
    width: 32,
  );
  static const hGap48 = SizedBox(
    width: 48,
  );

  static const edgeInsetsH4 = EdgeInsets.symmetric(horizontal: 4);
  static const edgeInsetsH8 = EdgeInsets.symmetric(horizontal: 8);
  static const edgeInsetsH12 = EdgeInsets.symmetric(horizontal: 12);
  static const edgeInsetsH16 = EdgeInsets.symmetric(horizontal: 16);
  static const edgeInsetsH20 = EdgeInsets.symmetric(horizontal: 20);
  static const edgeInsetsH24 = EdgeInsets.symmetric(horizontal: 24);

  static const edgeInsetsV4 = EdgeInsets.symmetric(vertical: 4);
  static const edgeInsetsV8 = EdgeInsets.symmetric(vertical: 8);
  static const edgeInsetsV12 = EdgeInsets.symmetric(vertical: 12);
  static const edgeInsetsV24 = EdgeInsets.symmetric(vertical: 24);

  static const edgeInsetsA4 = EdgeInsets.all(4);
  static const edgeInsetsA8 = EdgeInsets.all(8);
  static const edgeInsetsA12 = EdgeInsets.all(12);
  static const edgeInsetsA16 = EdgeInsets.all(16);
  static const edgeInsetsA20 = EdgeInsets.all(20);
  static const edgeInsetsA24 = EdgeInsets.all(24);

  static const edgeInsetsR4 = EdgeInsets.only(right: 4);
  static const edgeInsetsR8 = EdgeInsets.only(right: 8);
  static const edgeInsetsR12 = EdgeInsets.only(right: 12);
  static const edgeInsetsR16 = EdgeInsets.only(right: 16);
  static const edgeInsetsR20 = EdgeInsets.only(right: 20);
  static const edgeInsetsR24 = EdgeInsets.only(right: 24);

  static const edgeInsetsL4 = EdgeInsets.only(left: 4);
  static const edgeInsetsL8 = EdgeInsets.only(left: 8);
  static const edgeInsetsL12 = EdgeInsets.only(left: 12);
  static const edgeInsetsL16 = EdgeInsets.only(left: 16);
  static const edgeInsetsL20 = EdgeInsets.only(left: 20);
  static const edgeInsetsL24 = EdgeInsets.only(left: 24);

  static const edgeInsetsT4 = EdgeInsets.only(top: 4);
  static const edgeInsetsT8 = EdgeInsets.only(top: 8);
  static const edgeInsetsT12 = EdgeInsets.only(top: 12);
  static const edgeInsetsT24 = EdgeInsets.only(top: 24);

  static const edgeInsetsB4 = EdgeInsets.only(bottom: 4);
  static const edgeInsetsB8 = EdgeInsets.only(bottom: 8);
  static const edgeInsetsB12 = EdgeInsets.only(bottom: 12);
  static const edgeInsetsB24 = EdgeInsets.only(bottom: 24);

  static BorderRadius radius4 = BorderRadius.circular(4);
  static BorderRadius radius8 = BorderRadius.circular(8);
  static BorderRadius radius12 = BorderRadius.circular(12);
  static BorderRadius radius24 = BorderRadius.circular(24);
  static BorderRadius radius32 = BorderRadius.circular(32);
  static BorderRadius radius48 = BorderRadius.circular(48);

  /// 顶部状态栏的高度
  static double get statusBarHeight => MediaQuery.of(Get.context!).padding.top;

  /// 底部导航条的高度
  static double get bottomBarHeight {
    final mediaQuery = MediaQuery.of(Get.context!);
    final viewPadding = mediaQuery.viewPadding.bottom;
    final padding = mediaQuery.padding.bottom;
    return viewPadding > padding ? viewPadding : padding;
  }

  static EdgeInsets pagePadding({
    double horizontal = 12,
    double top = 12,
    double bottom = 12,
  }) {
    return EdgeInsets.fromLTRB(
      horizontal,
      top,
      horizontal,
      bottomBarHeight + bottom,
    );
  }

  static EdgeInsets bottomSheetPadding({
    double left = 0,
    double top = 0,
    double right = 0,
    double bottom = 12,
  }) {
    return EdgeInsets.fromLTRB(
      left,
      top,
      right,
      bottomBarHeight + bottom,
    );
  }

  static Divider get divider => Divider(
        height: 1,
        thickness: 1,
        indent: 16,
        endIndent: 16,
        color: Colors.grey.withAlpha(25),
      );
}
