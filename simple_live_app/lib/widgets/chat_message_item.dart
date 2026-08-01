import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
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

    Widget content({required TextStyle userStyle, required TextStyle messageStyle}) {
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
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withAlpha(25),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: content(
                      userStyle: TextStyle(color: Colors.grey, fontSize: textSize),
                      messageStyle: TextStyle(
                        color: Get.isDarkMode ? Colors.white : AppColors.black333,
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
  static final RegExp _emojiTokenPattern = RegExp(r'\[[^\[\]]{1,16}\]');

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
              _buildImageSpan(span.imageUrl!.trim()),
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

    final result = <InlineSpan>[];
    var start = 0;
    var imageIndex = 0;
    for (final match in _emojiTokenPattern.allMatches(message)) {
      if (imageIndex >= urls.length) {
        break;
      }
      if (match.start > start) {
        result.add(TextSpan(text: message.substring(start, match.start)));
      }
      result.add(_buildImageSpan(urls[imageIndex]));
      imageIndex += 1;
      start = match.end;
    }
    if (start < message.length) {
      result.add(TextSpan(text: message.substring(start)));
    }
    for (; imageIndex < urls.length; imageIndex += 1) {
      result.add(_buildImageSpan(urls[imageIndex]));
    }
    return result;
  }

  WidgetSpan _buildImageSpan(String url) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: NetImage(
          url,
          width: (messageStyle.fontSize ?? 14) * 1.35,
          height: (messageStyle.fontSize ?? 14) * 1.35,
          fit: BoxFit.contain,
        ),
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
