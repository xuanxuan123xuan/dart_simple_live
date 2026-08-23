import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/log.dart';

typedef TextValidate = bool Function(String text);

class Utils {
  static int _rightDialogRequest = 0;
  static Route<void>? _rightDialogRoute;
  static NavigatorState? _rightDialogNavigator;
  static Future<void>? _rightDialogFuture;
  static bool get isOhos => Platform.operatingSystem == 'ohos';

  static late PackageInfo packageInfo;
  static DateFormat dateFormat = DateFormat("MM-dd HH:mm");
  static DateFormat dateFormatWithYear = DateFormat("yyyy-MM-dd HH:mm");
  static DateFormat timeFormat = DateFormat("HH:mm:ss");

  /// 处理时间
  static String parseTime(DateTime? dt) {
    if (dt == null) {
      return "";
    }

    var dtNow = DateTime.now();
    if (dt.year == dtNow.year &&
        dt.month == dtNow.month &&
        dt.day == dtNow.day) {
      return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    }

    if (dt.year == dtNow.year) {
      return dateFormat.format(dt);
    }

    return dateFormatWithYear.format(dt);
  }

  /// 提示弹窗
  /// - `content` 内容
  /// - `title` 弹窗标题
  /// - `confirm` 确认按钮内容，留空为确定
  /// - `cancel` 取消按钮内容，留空为取消
  static Future<bool> showAlertDialog(
    String content, {
    String title = '',
    String confirm = '',
    String cancel = '',
    bool selectable = false,
    List<Widget>? actions,
  }) async {
    var result = await showDialogSafe<bool>(
      context: Get.context!,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Container(
          constraints: BoxConstraints(
            // 屏幕 30% 高（clamp 160-420）：鸿蒙字体缩放/小屏下 content
            // 过高会把 actions 挤出（BOTTOM OVERFLOWED 27px）。
            // content 内部 SingleChildScrollView 滚动看全文，按钮固定。
            maxHeight: (MediaQuery.sizeOf(dialogContext).height * 0.3)
                .clamp(160.0, 420.0),
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: AppStyle.edgeInsetsV12,
              child: selectable ? SelectableText(content) : Text(content),
            ),
          ),
        ),
        actions: [
          ...?actions,
          TextButton(
            onPressed: (() => Get.back(result: false)),
            child: Text(cancel.isEmpty ? "取消" : cancel),
          ),
          TextButton(
            onPressed: (() => Get.back(result: true)),
            child: Text(confirm.isEmpty ? "确定" : confirm),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 提示弹窗
  /// - `content` 内容
  /// - `title` 弹窗标题
  /// - `confirm` 确认按钮内容，留空为确定
  static Future<bool> showMessageDialog(String content,
      {String title = '', String confirm = '', bool selectable = false}) async {
    var result = await showDialogSafe<bool>(
      context: Get.context!,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Padding(
          padding: AppStyle.edgeInsetsV12,
          child: selectable ? SelectableText(content) : Text(content),
        ),
        actions: [
          TextButton(
            onPressed: (() => Get.back(result: true)),
            child: Text(confirm.isEmpty ? "确定" : confirm),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  static void showRightDialog({
    required String title,
    Function()? onDismiss,
    required Widget child,
    double width = 320,
    bool useSystem = false,
    bool clickMaskDismiss = true,
  }) {
    // `useSystem` is kept for source compatibility with existing callers.
    // Right-side panels are always Navigator routes now, so they cannot leak
    // through SmartDialog's process-wide custom-dialog queue.
    final request = ++_rightDialogRequest;
    // 等当前点击手势和外层播放器的 rebuild 完成后再创建路由，
    // 避免新弹窗的 barrier 接收到触发按钮的同一次点击。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (request != _rightDialogRequest) return;
      unawaited(
        _openRightDialog(
          request: request,
          title: title,
          onDismiss: onDismiss,
          child: child,
          width: width,
          clickMaskDismiss: clickMaskDismiss,
        ),
      );
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  static Future<void> _openRightDialog({
    required int request,
    required String title,
    required Function()? onDismiss,
    required Widget child,
    required double width,
    required bool clickMaskDismiss,
  }) async {
    await _dismissRightDialog();
    if (request != _rightDialogRequest) return;

    final context = Get.overlayContext ?? Get.context;
    if (context == null || !context.mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = _RightSideDialogRoute(
      title: title,
      width: width,
      clickOutsideDismiss: clickMaskDismiss,
      onHeaderBack: () async {
        Log.d('RightSideDialogRoute: onHeaderBack title=$title');
        await _dismissRightDialog();
        onDismiss?.call();
      },
      onCovered: _dismissRightDialog,
      child: child,
    );
    _rightDialogRoute = route;
    _rightDialogNavigator = navigator;
    Log.d('RightSideDialogRoute: opened title=$title request=$request\n${StackTrace.current}');
    final routeFuture = navigator.push<void>(route);
    // 前 1000ms 禁用 barrier 点击（拦截触摸穿透，重复事件约 300-400ms 延迟），
    // 之后启用正常遮罩关闭。Timer 可取消，route dispose 时避免跨测试残留。
    route.scheduleBarrierEnable();
    _rightDialogFuture = routeFuture;
    unawaited(
      routeFuture.whenComplete(() {
        if (identical(_rightDialogRoute, route)) {
          _rightDialogRoute = null;
          _rightDialogNavigator = null;
          _rightDialogFuture = null;
        }
      }),
    );
  }

  static Future<void> _dismissRightDialog() async {
    final route = _rightDialogRoute;
    final navigator = _rightDialogNavigator;
    final routeFuture = _rightDialogFuture;
    _rightDialogRoute = null;
    _rightDialogNavigator = null;
    _rightDialogFuture = null;
    if (route == null || navigator == null) return;
    Log.d('RightSideDialogRoute: dismiss called (isCurrent=${route.isCurrent}, isActive=${route.isActive})\n${StackTrace.current}');
    if (route.isCurrent) {
      navigator.pop<void>();
    } else if (route.isActive) {
      navigator.removeRoute(route);
    }
    if (routeFuture != null) {
      await routeFuture;
    }
  }

  static void hideRightDialog() {
    _rightDialogRequest += 1;
    Log.d('RightSideDialogRoute: hideRightDialog called\n${StackTrace.current}');
    unawaited(_dismissRightDialog());
  }

  /// 测试专用：重置右侧面板的静态状态，避免跨测试残留
  /// （tearDown 中 hideRightDialog 是异步的，Get.reset() 后残留的
  ///  route/navigator 已 dispose，访问会抛异常）。
  @visibleForTesting
  static void debugResetRightDialog() {
    _rightDialogRequest = 0;
    _rightDialogRoute = null;
    _rightDialogNavigator = null;
    _rightDialogFuture = null;
  }

  static Future<void> switchRightDialog(
    FutureOr<void> Function() openNext,
  ) async {
    _rightDialogRequest += 1;
    Log.d('RightSideDialogRoute: switchRightDialog called\n${StackTrace.current}');
    await _dismissRightDialog();
    await Future.delayed(const Duration(milliseconds: 220));
    await openNext();
  }

  static Future showBottomSheet({
    required String title,
    required Widget child,
    double maxWidth = 600,
    double? maxHeightFactor,
  }) async {
    final context = Get.context;
    if (context == null) return null;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = _RightSideSheetRoute(
      title: title,
      child: child,
      maxWidth: maxWidth,
      maxHeightFactor: maxHeightFactor,
    );
    // 前 1000ms 禁用 barrier 点击（拦截 LiveContainer/iOS26 触摸穿透），
    // 与右侧弹窗同一套防护。
    route.scheduleBarrierEnable();
    return navigator.push<void>(route);
  }

  /// 通用底部弹窗（替代 showModalBottomSheet），带 barrier 1000ms 防穿透窗口。
  /// 参数与 showModalBottomSheet 常用子集对齐。
  static Future<T?> showModalBottomSheetSafe<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    bool showDragHandle = false,
    bool useSafeArea = false,
    BoxConstraints? constraints,
    ShapeBorder? shape,
    Color? backgroundColor,
  }) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = _SafeBottomSheetRoute<T>(
      builder: builder,
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      useSafeArea: useSafeArea,
      constraints: constraints,
      shape: shape,
      backgroundColor: backgroundColor,
      alignment: Alignment.bottomCenter,
      dismissByBarrier: true,
    );
    // 前 1000ms 禁用 barrier 点击（拦截 LiveContainer/iOS26 触摸穿透）。
    route.scheduleBarrierEnable();
    return navigator.push<T>(route);
  }

  /// 通用居中弹窗（替代 Get.dialog / showDialog），带 barrier 1000ms 防穿透窗口。
  static Future<T?> showDialogSafe<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool dismissByBarrier = true,
    // 默认开启键盘避让：含 TextField 的对话框（搜索/编辑/粘贴等）
    // 弹键盘时自动上移，不再被压缩溢出。无键盘对话框无副作用。
    bool isScrollControlled = true,
  }) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = _SafeBottomSheetRoute<T>(
      builder: builder,
      isScrollControlled: isScrollControlled,
      showDragHandle: false,
      useSafeArea: false,
      constraints: null,
      shape: null,
      backgroundColor: Colors.transparent,
      alignment: Alignment.center,
      dismissByBarrier: dismissByBarrier,
    );
    // 前 1000ms 禁用 barrier 点击（拦截 LiveContainer/iOS26 触摸穿透）。
    route.scheduleBarrierEnable();
    return navigator.push<T>(route);
  }

  static Widget bottomSheetSafeArea({
    required Widget child,
    double bottom = 12,
  }) {
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: AppStyle.bottomSheetPadding(bottom: bottom),
        child: child,
      ),
    );
  }

  /// 文本编辑的弹窗
  /// - `content` 编辑框默认的内容
  /// - `title` 弹窗标题
  /// - `confirm` 确认按钮内容
  /// - `cancel` 取消按钮内容
  static Future<String?> showEditTextDialog(
    String content, {
    String title = '',
    String? hintText,
    String confirm = '',
    String cancel = '',
    TextValidate? validate,
  }) async {
    final TextEditingController textEditingController =
        TextEditingController(text: content);
    var result = await showDialogSafe<String>(
      context: Get.context!,
      // 键盘避让：输入框弹键盘时对话框上移，不再溢出。
      isScrollControlled: true,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Padding(
          padding: AppStyle.edgeInsetsT12,
          child: TextField(
            controller: textEditingController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              //prefixText: title,
              contentPadding: AppStyle.edgeInsetsA12,
              hintText: hintText ?? title,
            ),
            // style: TextStyle(
            //     height: 1.0,
            //     color: Get.isDarkMode ? Colors.white : Colors.black),
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              if (validate != null && !validate(textEditingController.text)) {
                return;
              }

              Get.back(result: textEditingController.text);
            },
            child: const Text("确定"),
          ),
        ],
      ),
      // barrierColor:
      //     Get.isDarkMode ? Colors.grey.withOpacity(.3) : Colors.black38,
    );
    return result;
  }

  static Future<T?> showOptionDialog<T>(
    List<T> contents,
    T value, {
    String title = '',
  }) async {
    var result = await showDialogSafe<T>(
      context: Get.context!,
      builder: (_) => SimpleDialog(
        title: Text(title),
        children: [
          RadioGroup<T>(
            groupValue: value,
            onChanged: (selected) => Get.back(result: selected),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: contents
                  .map(
                    (e) => RadioListTile<T>(
                      title: Text(e.toString()),
                      value: e,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
    return result;
  }

  /// 多段指引用户内容的弹窗
  /// - `content` 内容：可滚动
  /// - `title` 顶部弹窗标题
  /// - `actions` 底部按钮
  static Future<T?> showInformationHelpDialog<T>({
    required List<Widget> content,
    Widget? title,
    List<Widget>? actions,
  }) async {
    var result = await showDialogSafe<dynamic>(
      context: Get.context!,
      builder: (_) => AlertDialog(
        title: title ?? const Text("帮助"),
        scrollable: true,
        content: SingleChildScrollView(child: ListBody(children: content)),
        actions: actions ??
            [
              TextButton(
                onPressed: Get.back,
                child: const Text("确定"),
              ),
            ],
      ),
    );
    return result;
  }

  static Future showStatement() async {
    var text = await rootBundle.loadString("assets/statement.txt");

    var result = await showAlertDialog(
      text,
      selectable: true,
      title: "免责声明",
      confirm: "已阅读并同意",
      cancel: "退出",
    );
    if (!result) {
      exit(0);
    }
  }

  static Future<T?> showMapOptionDialog<T>(
    Map<T, String> contents,
    T value, {
    String title = '',
  }) async {
    var result = await showDialogSafe<T>(
      context: Get.context!,
      builder: (_) => SimpleDialog(
        title: Text(title),
        children: [
          RadioGroup<T>(
            groupValue: value,
            onChanged: (selected) => Get.back(result: selected),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: contents.keys
                  .map(
                    (e) => RadioListTile<T>(
                      title: Text((contents[e] ?? '-').tr),
                      value: e,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
    return result;
  }

  static int parseVersion(String version) {
    var sp = version.split('.');
    var num = "";
    for (var item in sp) {
      num = num + item.padLeft(2, '0');
    }
    return int.parse(num);
  }

  static String onlineToString(int num) {
    if (num >= 10000) {
      return "${(num / 10000.0).toStringAsFixed(1)}万";
    }
    return num.toString();
  }

  /// 检查相册权限
  static Future<bool> checkPhotoPermission() async {
    try {
      if (!Platform.isIOS) {
        return true;
      }
      var status = await Permission.photos.status;
      if (status == PermissionStatus.granted) {
        return true;
      }
      status = await Permission.photos.request();
      if (status.isGranted) {
        return true;
      } else {
        SmartDialog.showToast(
          "请授予相册访问权限",
        );
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  static final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

  /// 检查文件权限
  static Future<bool> checkStorgePermission() async {
    try {
      if (!Platform.isAndroid || Utils.isOhos) {
        return true;
      }
      Permission permission = Permission.storage;
      var androidIndo = await deviceInfo.androidInfo;
      if (androidIndo.version.sdkInt >= 33) {
        permission = Permission.manageExternalStorage;
      }

      var status = await permission.status;
      if (status == PermissionStatus.granted) {
        return true;
      }
      status = await permission.request();
      if (status.isGranted) {
        return true;
      } else {
        SmartDialog.showToast(
          "请授予文件访问权限",
        );
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  ///16进制颜色转换
  static Color convertHexColor(String hexColor) {
    hexColor = hexColor.replaceAll("#", "");
    if (hexColor.length == 4) {
      hexColor = "00$hexColor";
    }

    if (hexColor.length == 6) {
      var R = int.parse(hexColor.substring(0, 2), radix: 16);
      var G = int.parse(hexColor.substring(2, 4), radix: 16);
      var B = int.parse(hexColor.substring(4, 6), radix: 16);
      return Color.fromARGB(255, R, G, B);
    }
    if (hexColor.length == 8) {
      var A = int.parse(hexColor.substring(0, 2), radix: 16);
      var R = int.parse(hexColor.substring(2, 4), radix: 16);
      var G = int.parse(hexColor.substring(4, 6), radix: 16);
      var B = int.parse(hexColor.substring(6, 8), radix: 16);

      return Color.fromARGB(A, R, G, B);
    }

    return Colors.white;
  }

  /// 复制内容到剪贴板
  static void copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      SmartDialog.showToast("已复制到剪贴板");
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("复制到剪贴板失败: $e");
    }
  }

  /// 获取剪贴板内容
  static Future<String?> getClipboard() async {
    try {
      var content = await Clipboard.getData(Clipboard.kTextPlain);
      if (content == null) {
        SmartDialog.showToast("无法读取剪贴板内容");
        return null;
      }
      return content.text;
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("读取剪切板内容失败：$e");
    }
    return null;
  }

  static bool isRegexFormat(String keyword) {
    return keyword.startsWith('/') &&
        keyword.endsWith('/') &&
        keyword.length > 2;
  }

  static String removeRegexFormat(String keyword) {
    return keyword.substring(1, keyword.length - 1);
  }

  static String parseFileSize(int size) {
    if (size < 1024) {
      return "$size B";
    }
    if (size < 1024 * 1024) {
      return "${(size / 1024).toStringAsFixed(2)} KB";
    }
    if (size < 1024 * 1024 * 1024) {
      return "${(size / 1024 / 1024).toStringAsFixed(2)} MB";
    }
    return "${(size / 1024 / 1024 / 1024).toStringAsFixed(2)} GB";
  }
}

/// A route-local right-side panel.
///
/// Keeping this panel in the Navigator avoids adding it to SmartDialog's
/// process-wide custom-dialog queue. Toasts and loading indicators can still
/// use SmartDialog, while a player panel is removed by normal route lifecycle.
class _RightSideDialogRoute extends PopupRoute<void> {
  _RightSideDialogRoute({
    required this.title,
    required this.width,
    required this.clickOutsideDismiss,
    required this.onHeaderBack,
    required this.onCovered,
    required this.child,
  });

  final String title;
  final double width;
  final bool clickOutsideDismiss;
  final Future<void> Function() onHeaderBack;
  final Future<void> Function() onCovered;
  final Widget child;

  /// 弹窗 push 后前 1000ms 禁用 barrier 点击（拦截 LiveContainer/iOS26
  /// 触摸事件重复：第一次触发 onPressed 开弹窗，第二次落在 barrier 上关闭。
  /// 重复事件约 300-400ms 延迟，1000ms 后 enableBarrier() 启用，用户真实点击
  /// 遮罩（>1s）正常关闭。
  bool _barrierEnabled = false;
  bool _disposed = false;
  Timer? _barrierTimer;

  void scheduleBarrierEnable() {
    _barrierTimer?.cancel();
    _barrierTimer = Timer(const Duration(milliseconds: 1000), () {
      if (_disposed || !isActive) {
        return;
      }
      enableBarrier();
      Log.d('RightSideDialogRoute: barrier enabled title=$title');
    });
  }

  void enableBarrier() {
    _barrierEnabled = true;
    // 通知 _ModalScope 重建，让 barrier 的点击响应读到新的 barrierDismissible。
    changedExternalState();
  }

  @override
  bool get barrierDismissible => _barrierEnabled && clickOutsideDismiss;

  @override
  void dispose() {
    _barrierTimer?.cancel();
    _disposed = true;
    Log.d('RightSideDialogRoute disposed (title=$title, isCurrent=$isCurrent, isActive=$isActive)\n${StackTrace.current}');
    super.dispose();
  }

  @override
  void didComplete(void result) {
    Log.d('RightSideDialogRoute: didComplete title=$title (pop 完成)\n${StackTrace.current}');
    super.didComplete(result);
  }

  @override
  void onPopInvokedWithResult(bool didPop, dynamic result) {
    Log.d('RightSideDialogRoute: onPopInvoked title=$title didPop=$didPop\n${StackTrace.current}');
    // PopupRoute<void> 的 result 是 void?，只能传 null。
    super.onPopInvokedWithResult(didPop, null);
  }

  @override
  void didPopNext(Route<dynamic> nextRoute) {
    Log.d('RightSideDialogRoute: didPopNext title=$title next=${nextRoute.runtimeType}');
    super.didPopNext(nextRoute);
  }

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    super.didChangeNext(nextRoute);
    Log.d('RightSideDialogRoute: didChangeNext title=$title next=${nextRoute?.runtimeType} completed=${animation?.isCompleted} isCurrent=$isCurrent isActive=$isActive');
    if (nextRoute == null) return;
    // 只响应真正的页面导航（PageRoute）。SmartDialog toast、Get.bottomSheet
    // 等浮层（PopupRoute）覆盖时不应关闭右侧面板——否则弹窗打开瞬间若有
    // 任何浮层 route push（如自动降画质 toast），弹窗会"刚打开就消失"。
    if (nextRoute is! PageRoute) return;
    // 防御：入场动画尚未完成时的 PageRoute 覆盖多为手势/系统竞态，
    // 忽略，避免"点开不到一秒自动关闭"。（不依赖墙钟，测试可控。）
    if (animation?.isCompleted != true) return;
    // A page was pushed on top: remove this transient panel after the push
    // settles so it cannot contaminate the destination or reappear on return.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isActive && !isCurrent) {
        Log.d('RightSideDialogRoute: covered by ${nextRoute.runtimeType}, dismissing');
        unawaited(onCovered());
      }
    });
  }

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  String? get barrierLabel => "关闭侧边弹窗";

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final mediaQuery = MediaQuery.of(context);
    // `width` is the panel's final visual width. Keep the system-safe inset
    // inside that width; adding it here makes Android landscape panels wider
    // whenever the navigation bar occupies the right edge.
    final panelWidth = width.clamp(0.0, mediaQuery.size.width).toDouble();
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        key: const ValueKey<String>('right-side-dialog-panel'),
        width: panelWidth,
        height: mediaQuery.size.height,
        child: Material(
          color: Theme.of(context).cardColor,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(4),
              bottomLeft: Radius.circular(4),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: EdgeInsets.only(right: mediaQuery.padding.right),
            child: SafeArea(
              left: false,
              right: false,
              child: Column(
                children: [
                  ListTile(
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    leading: IconButton(
                      onPressed: () => unawaited(onHeaderBack()),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    title: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: Colors.grey.withAlpha(25),
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(curved),
      child: child,
    );
  }
}

/// 底部弹窗（替代 showModalBottomSheet），带 barrier 1000ms 防穿透窗口。
/// 视觉与 showModalBottomSheet 一致（底部圆角、maxWidth 约束、SafeArea）。
class _RightSideSheetRoute extends PopupRoute<void> {
  _RightSideSheetRoute({
    required this.title,
    required this.child,
    required this.maxWidth,
    required this.maxHeightFactor,
  });

  final String title;
  final Widget child;
  final double maxWidth;
  final double? maxHeightFactor;

  bool _barrierEnabled = false;
  bool _disposed = false;
  Timer? _barrierTimer;

  void scheduleBarrierEnable() {
    _barrierTimer?.cancel();
    _barrierTimer = Timer(const Duration(milliseconds: 1000), () {
      if (_disposed || !isActive) {
        return;
      }
      _barrierEnabled = true;
      changedExternalState();
    });
  }

  @override
  bool get barrierDismissible => _barrierEnabled;

  @override
  Color? get barrierColor => Colors.black54;

  @override
  String? get barrierLabel => "关闭";

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final mediaQuery = MediaQuery.of(context);
    final heightFactor = maxHeightFactor;
    final maxHeight = heightFactor == null
        ? double.infinity
        : mediaQuery.size.height * heightFactor;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
          ),
        ),
        child: SafeArea(
          top: true,
          bottom: false,
          child: Padding(
            padding: AppStyle.bottomSheetPadding(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 12),
                  title: Text(title),
                  trailing: IconButton(
                    onPressed: Get.back,
                    icon: const Icon(Remix.close_line),
                  ),
                ),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(curved),
      child: child,
    );
  }

  @override
  void dispose() {
    _barrierTimer?.cancel();
    _disposed = true;
    super.dispose();
  }
}

/// 通用底部弹窗 route（替代 showModalBottomSheet），带 barrier 1000ms 防穿透窗口。
class _SafeBottomSheetRoute<T> extends PopupRoute<T> {
  _SafeBottomSheetRoute({
    required this.builder,
    required this.isScrollControlled,
    required this.showDragHandle,
    required this.useSafeArea,
    required this.constraints,
    required this.shape,
    required this.backgroundColor,
    required this.alignment,
    required this.dismissByBarrier,
  });

  final WidgetBuilder builder;
  final bool isScrollControlled;
  final bool showDragHandle;
  final bool useSafeArea;
  final BoxConstraints? constraints;
  final ShapeBorder? shape;
  final Color? backgroundColor;
  final AlignmentGeometry alignment;
  final bool dismissByBarrier;

  bool _barrierEnabled = false;
  bool _disposed = false;
  Timer? _barrierTimer;

  void scheduleBarrierEnable() {
    _barrierTimer?.cancel();
    _barrierTimer = Timer(const Duration(milliseconds: 1000), () {
      if (_disposed || !isActive) {
        return;
      }
      _barrierEnabled = true;
      changedExternalState();
    });
  }

  @override
  bool get barrierDismissible => _barrierEnabled && dismissByBarrier;

  @override
  Color? get barrierColor => Colors.black54;

  @override
  String? get barrierLabel => "关闭";

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = isScrollControlled
        ? mediaQuery.size.height * 0.9
        : mediaQuery.size.height * 0.5;
    return Align(
      alignment: alignment,
      child: Container(
        // 不做键盘避让（不按 viewInsets 上移）：输入框在屏幕中间，
        // 键盘一般比它矮不会遮挡，保持位置稳定。
        constraints: BoxConstraints(
          maxWidth: constraints?.maxWidth ?? double.infinity,
          maxHeight: maxHeight,
        ),
        decoration: ShapeDecoration(
          color: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
          shape: shape ??
              const RoundedRectangleBorder(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
        ),
        child: SafeArea(
          top: useSafeArea,
          bottom: useSafeArea,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showDragHandle)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              Flexible(child: Builder(builder: builder)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(curved),
      child: child,
    );
  }

  @override
  void dispose() {
    _barrierTimer?.cancel();
    _disposed = true;
    super.dispose();
  }
}
