import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/glass_quality_policy.dart';
import 'package:simple_live_app/widgets/glass/glass_surface.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 单条聊天消息（对齐正常直播间聊天 Tab 的渲染）。
///
/// - 系统消息（userName == "LiveSysMessage"）→ 灰色纯文本
/// - 普通消息 → [ChatMessageText]，可选气泡样式
class ChatMessageItem extends StatelessWidget {
  final LiveMessage message;

  /// 用户名备注（如 `[房管]`），可为空。
  final String? remark;

  final VoidCallback? onUserTap;
  final VoidCallback? onUserLongPress;

  const ChatMessageItem({
    super.key,
    required this.message,
    this.remark,
    this.onUserTap,
    this.onUserLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (message.userName == "LiveSysMessage") {
      return Obx(
        () => Text(
          message.message,
          style: TextStyle(
            color: Colors.grey,
            fontSize: AppSettingsController.instance.chatTextSize.value,
          ),
        ),
      );
    }

    final settings = AppSettingsController.instance;
    final emojiEnabled = settings.danmuRenderEmoji.value;

    Widget content(
        {required TextStyle userStyle, required TextStyle messageStyle}) {
      return ChatMessageText(
        userName: message.userName,
        remark: remark,
        message: message.message,
        imageUrls: emojiEnabled ? message.imageUrls : null,
        spans: emojiEnabled ? message.spans : null,
        userStyle: userStyle,
        messageStyle: messageStyle,
        onUserTap: onUserTap,
        onUserLongPress: onUserLongPress,
      );
    }

    final textSize = settings.chatTextSize.value;
    return Obx(
      () => settings.chatBubbleStyle.value
          ? Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: GlassSurface(
                    role: GlassSurfaceRole.content,
                    radius: 12,
                    fallbackBorder: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: content(
                      userStyle:
                          TextStyle(color: Colors.grey, fontSize: textSize),
                      messageStyle: TextStyle(
                        color:
                            Get.isDarkMode ? Colors.white : AppColors.black333,
                        fontSize: textSize,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : content(
              userStyle: TextStyle(color: Colors.grey, fontSize: textSize),
              messageStyle: TextStyle(
                color: Get.isDarkMode ? Colors.white : AppColors.black333,
                fontSize: textSize,
              ),
            ),
    );
  }
}

/// 用户名 + 备注 + 正文（含表情图片原位渲染），点击/长按用户交互。
class ChatMessageText extends StatelessWidget {
  static final RegExp _emojiTokenPattern = RegExp(r'\[[^\[\]\r\n]{1,64}\]');

  final String userName;
  final String? remark;
  final String message;
  final List<String>? imageUrls;
  final List<LiveMessageSpan>? spans;
  final TextStyle userStyle;
  final TextStyle messageStyle;
  final VoidCallback? onUserTap;
  final VoidCallback? onUserLongPress;

  const ChatMessageText({
    super.key,
    required this.userName,
    this.remark,
    required this.message,
    this.imageUrls,
    this.spans,
    required this.userStyle,
    required this.messageStyle,
    this.onUserTap,
    this.onUserLongPress,
  });

  TextSpan _buildTextSpan() {
    final richSpans = spans ?? const <LiveMessageSpan>[];
    return TextSpan(
      style: messageStyle,
      children: [
        TextSpan(
          text: '$userName：',
          style: userStyle,
        ),
        if ((remark ?? "").trim().isNotEmpty)
          TextSpan(
            text: '[${remark!.trim()}] ',
            style: userStyle.copyWith(
              color: userStyle.color?.withAlpha(180),
              fontSize: (userStyle.fontSize ?? 14) - 1,
            ),
          ),
        if (richSpans.isNotEmpty)
          for (final span in richSpans)
            if (span.isText)
              TextSpan(text: span.text)
            else if (span.isImage)
              _buildImageSpan(
                span.imageUrl!.trim(),
                fallbackText: span.fallbackText,
              ),
        if (richSpans.isEmpty) ...[
          ..._buildFallbackContentSpans(),
        ],
      ],
    );
  }

  List<InlineSpan> _buildFallbackContentSpans() {
    final urls = (imageUrls ?? const <String>[])
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList();
    if (urls.isEmpty) {
      return [TextSpan(text: message)];
    }

    final matches = _emojiTokenPattern.allMatches(message).toList(
          growable: false,
        );
    final (tokenUrls, consumedUrls) = _pairTokensWithUrls(matches, urls);

    final result = <InlineSpan>[];
    var start = 0;
    for (var i = 0; i < matches.length; i++) {
      final url = tokenUrls[i];
      if (url == null) {
        // 没有地址可配对，token 原文留在待输出的文本区间里，避免丢字
        continue;
      }
      final match = matches[i];
      if (match.start > start) {
        result.add(TextSpan(text: message.substring(start, match.start)));
      }
      result.add(
        _buildImageSpan(
          url,
          fallbackText: match.group(0),
        ),
      );
      start = match.end;
    }
    if (start < message.length) {
      result.add(TextSpan(text: message.substring(start)));
    }
    // 有些站点会给出文本里没有对应 token 的图片，剩余地址仍追加到末尾
    for (var i = consumedUrls; i < urls.length; i += 1) {
      result.add(_buildImageSpan(urls[i]));
    }
    return result;
  }

  /// 把文本里的表情 token 与 [urls] 配对，返回每个 token 的地址（配不上时为
  /// null）以及已消耗的地址数量。
  ///
  /// 各站点的 [LiveMessage.imageUrls] 都是 `.toSet().toList()` 去重后的结果，
  /// 重复表情只剩一个地址，按下标逐个配对会让第二次及以后的重复 token 退化成
  /// 字面量文本。所以 token 数超过地址数时几乎必然是被去重过：改为按「首次出现
  /// 顺序」给去重后的 token 分配地址，同一 token 的每次出现复用同一地址，正好
  /// 抵消上游的去重。
  static (List<String?>, int) _pairTokensWithUrls(
    List<RegExpMatch> matches,
    List<String> urls,
  ) {
    if (matches.length <= urls.length) {
      // 数量本就对得上，说明没被去重影响，保持原有的按位配对
      return (
        List<String?>.generate(matches.length, (index) => urls[index]),
        matches.length,
      );
    }
    final urlByToken = <String, String>{};
    for (final match in matches) {
      final token = match.group(0)!;
      if (urlByToken.containsKey(token)) {
        continue;
      }
      if (urlByToken.length >= urls.length) {
        break;
      }
      urlByToken[token] = urls[urlByToken.length];
    }
    return (
      matches
          .map((match) => urlByToken[match.group(0)!])
          .toList(growable: false),
      urlByToken.length,
    );
  }

  WidgetSpan _buildImageSpan(String url, {String? fallbackText}) {
    final hasFallback = fallbackText?.isNotEmpty ?? false;
    final imageSize = (messageStyle.fontSize ?? 14) * 1.35;
    final fallback = SizedBox(
      width: imageSize,
      height: imageSize,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          fallbackText ?? '',
          style: messageStyle,
          maxLines: 1,
        ),
      ),
    );
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: NetImage(
        url,
        width: imageSize,
        height: imageSize,
        fit: BoxFit.contain,
        loadingWidget: hasFallback ? fallback : null,
        errorWidget: hasFallback ? fallback : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textSpan = _buildTextSpan();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onUserTap,
      onLongPress: onUserLongPress,
      child: Text.rich(
        textSpan,
        softWrap: true,
        textWidthBasis: TextWidthBasis.parent,
      ),
    );
  }
}
