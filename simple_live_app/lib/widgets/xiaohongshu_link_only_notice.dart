import 'package:flutter/material.dart';
import 'package:simple_live_core/simple_live_core.dart';

class XiaohongshuLinkOnlyNotice extends StatelessWidget {
  const XiaohongshuLinkOnlyNotice({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.link, size: 36),
          SizedBox(height: 12),
          Text(XiaohongshuDiscoveryClient.unavailableReason),
          SizedBox(height: 8),
          Text('在搜索框粘贴小红书直播分享链接即可进入。关注会保存在本地。', textAlign: TextAlign.center),
        ]),
      );
}
