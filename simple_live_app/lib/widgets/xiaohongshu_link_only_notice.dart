import 'package:flutter/material.dart';

class XiaohongshuLinkOnlyNotice extends StatelessWidget {
  const XiaohongshuLinkOnlyNotice({
    this.title = '小红书直播搜索暂不可用',
    this.errorMessage,
    this.onRetry,
    this.onOpenSearch,
    super.key,
  });

  final String title;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenSearch;

  @override
  Widget build(BuildContext context) {
    final message = errorMessage?.trim();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.link, size: 36),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
          ),
          if (message != null && message.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(message, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 8),
          const Text(
            '可以在搜索框粘贴小红书直播分享链接，直接进入直播间。',
            textAlign: TextAlign.center,
          ),
          if (onRetry != null || onOpenSearch != null) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                if (onRetry != null)
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                if (onOpenSearch != null)
                  TextButton.icon(
                    onPressed: onOpenSearch,
                    icon: const Icon(Icons.search),
                    label: const Text('粘贴链接进入'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
