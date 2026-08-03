import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/ohos_document_service.dart';

class DebugLogPage extends StatelessWidget {
  const DebugLogPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Log"),
        actions: [
          Builder(
            builder: (buttonContext) {
              return IconButton(
                onPressed: () async {
                  var msg = Log.debugLogs
                      .map((x) => "${x.datetime}\r\n${x.content}")
                      .join('\r\n\r\n');
                  // 用临时目录：Documents/Application Support 是 app 沙盒，
                  // 接收方 app 无权限读取，分享出去是 0 字节。
                  var dir = await getTemporaryDirectory();
                  var logFile = File(
                      '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.log');
                  await logFile.writeAsString(msg);

                  if (Utils.isOhos) {
                    try {
                      await OhosDocumentService.shareFile(
                        logFile.path,
                        title: 'Simple Live 调试日志',
                      );
                    } catch (e) {
                      Log.logPrint(e);
                    }
                    return;
                  }
                  // iPad 上 UIActivityViewController 需要 popover 锚点矩形，
                  // 否则分享面板定位失败/内容异常。
                  if (!buttonContext.mounted) return;
                  final box = buttonContext.findRenderObject() as RenderBox?;
                  Share.shareXFiles(
                    [XFile(logFile.path)],
                    sharePositionOrigin: box == null
                        ? null
                        : box.localToGlobal(Offset.zero) & box.size,
                  );
                },
                icon: const Icon(Icons.save),
              );
            },
          ),
          IconButton(
            onPressed: () {
              Log.debugLogs.clear();
            },
            icon: const Icon(Icons.clear_all),
          ),
        ],
      ),
      body: Obx(
        () => ListView.separated(
          itemCount: Log.debugLogs.length,
          separatorBuilder: (_, i) => const Divider(),
          padding: AppStyle.edgeInsetsA12,
          itemBuilder: (_, i) {
            var item = Log.debugLogs[i];
            return SelectableText(
              "${item.datetime.toString()}\r\n${item.content}",
              style: TextStyle(
                color: item.color,
                fontSize: 12,
              ),
            );
          },
        ),
      ),
    );
  }
}
