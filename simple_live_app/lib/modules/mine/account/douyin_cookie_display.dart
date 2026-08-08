import 'package:simple_live_core/simple_live_core.dart';

class DouyinCookieDisplay {
  const DouyinCookieDisplay._();

  static String summary(String cookie, {DateTime? now}) {
    final normalized = cookie.trim();
    if (normalized.isEmpty) {
      return "未配置自定义 Cookie（当前使用默认 ttwid），搜索需要完整登录 Cookie";
    }
    if (DouyinCookieHelper.isOnlyTtwid(normalized)) {
      return "仅配置 ttwid（播放兜底），搜索需要完整登录 Cookie";
    }
    if (!DouyinCookieHelper.hasLoginSession(normalized)) {
      return "已保存 Cookie，但缺少登录字段，搜索仍不可用";
    }

    final expiry = DouyinCookieHelper.parseExpiry(normalized);
    if (expiry == null) {
      return "已配置完整登录 Cookie（${normalized.length} 字符），有效期无法判断";
    }
    final referenceTime = now ?? DateTime.now();
    if (!expiry.isAfter(referenceTime)) {
      return "已配置完整登录 Cookie（${normalized.length} 字符），可解析有效期已过";
    }
    final remaining = expiry.difference(referenceTime);
    return "已配置完整登录 Cookie（${normalized.length} 字符），预计剩余 ${_formatDurationShort(remaining)}";
  }

  static String savedMessage(String cookie, {bool imported = false}) {
    final normalized = cookie.trim();
    if (DouyinCookieHelper.isOnlyTtwid(normalized)) {
      return imported
          ? "已导入 ttwid；仅可作为播放兜底，搜索仍需完整登录 Cookie"
          : "已保存 ttwid；仅可作为播放兜底，搜索仍需完整登录 Cookie";
    }
    if (!DouyinCookieHelper.hasLoginSession(normalized)) {
      return imported
          ? "Cookie 已导入，但未检测到登录字段；搜索仍不可用"
          : "Cookie 已保存，但未检测到登录字段；搜索仍不可用";
    }
    return imported ? "已导入完整抖音登录 Cookie" : "完整抖音登录 Cookie 已保存";
  }

  static String _formatDurationShort(Duration duration) {
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    if (days > 0) {
      return "$days 天 $hours 小时";
    }
    if (hours > 0) {
      return "$hours 小时 $minutes 分钟";
    }
    return "${duration.inMinutes} 分钟";
  }
}
