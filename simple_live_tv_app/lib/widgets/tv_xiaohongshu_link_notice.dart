import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/routes/app_navigation.dart';
import 'package:simple_live_tv_app/services/live_room_link_parser.dart';
import 'package:simple_live_tv_app/widgets/button/highlight_button.dart';
import 'package:simple_live_tv_app/widgets/tv_open_live_link_dialog.dart';

class TvXiaohongshuLinkNotice extends StatefulWidget {
  const TvXiaohongshuLinkNotice({super.key});

  @override
  State<TvXiaohongshuLinkNotice> createState() =>
      _TvXiaohongshuLinkNoticeState();
}

class _TvXiaohongshuLinkNoticeState extends State<TvXiaohongshuLinkNotice> {
  final _openFocus = AppFocusNode();

  @override
  void dispose() {
    _openFocus.dispose();
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
            const Text('小红书请通过直播链接或房间号进入',
                style: TextStyle(color: Colors.white, fontSize: 24)),
            const SizedBox(height: 12),
            const Text('也可以从关注和观看历史打开直播间',
                style: TextStyle(color: Colors.white70, fontSize: 18)),
            const SizedBox(height: 24),
            HighlightButton(
                focusNode: _openFocus,
                text: '打开直播间',
                iconData: Icons.link,
                onTap: _open),
          ]),
        ),
      );
}
