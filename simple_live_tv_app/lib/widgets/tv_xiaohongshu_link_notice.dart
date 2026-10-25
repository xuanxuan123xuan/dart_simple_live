import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/routes/app_navigation.dart';
import 'package:simple_live_tv_app/services/live_room_link_parser.dart';
import 'package:simple_live_tv_app/widgets/button/highlight_button.dart';
import 'package:simple_live_tv_app/widgets/tv_open_live_link_dialog.dart';

class TvXiaohongshuLinkNotice extends StatefulWidget {
  const TvXiaohongshuLinkNotice({
    this.title = '小红书直播发现暂不可用',
    this.errorMessage,
    this.onRetry,
    super.key,
  });

  final String title;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  State<TvXiaohongshuLinkNotice> createState() =>
      _TvXiaohongshuLinkNoticeState();
}

class _TvXiaohongshuLinkNoticeState extends State<TvXiaohongshuLinkNotice> {
  final _openFocus = AppFocusNode();
  final _retryFocus = AppFocusNode();

  @override
  void dispose() {
    _openFocus.dispose();
    _retryFocus.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final target = await Get.dialog<LiveRoomLinkTarget>(
      const TvOpenLiveLinkDialog(initialSiteId: Constant.kXiaohongshu),
    );
    if (!mounted || target == null) return;
    AppNavigator.toLiveRoomDetail(
      site: target.site,
      roomId: target.roomId,
      douyinSecUserId: target.douyinSecUserId,
      xiaohongshuHostId: target.xiaohongshuHostId,
    );
  }

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 24)),
            if (widget.errorMessage?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(widget.errorMessage!.trim(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16)),
            ],
            const SizedBox(height: 12),
            const Text('可以粘贴小红书直播分享链接或房间号直接进入',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 18)),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 24,
              runSpacing: 16,
              children: [
                if (widget.onRetry != null)
                  HighlightButton(
                    focusNode: _retryFocus,
                    text: '重试',
                    iconData: Icons.refresh,
                    autofocus: true,
                    onTap: widget.onRetry,
                  ),
                HighlightButton(
                  focusNode: _openFocus,
                  text: '打开直播间',
                  iconData: Icons.link,
                  onTap: _open,
                ),
              ],
            ),
          ]),
        ),
      );
}
