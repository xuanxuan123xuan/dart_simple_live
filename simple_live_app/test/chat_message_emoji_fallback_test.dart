import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/widgets/chat_message_item.dart';
import 'package:simple_live_app/widgets/net_image.dart';

/// 聊天正文在缺少 spans 时会退化到 imageUrls 配对路径，而各站点的 imageUrls 都被
/// `.toSet().toList()` 去重过，这里覆盖重复表情不再退化成字面量 token 的行为。
void main() {
  Future<TextSpan> pumpMessage(
    WidgetTester tester, {
    required String message,
    List<String>? imageUrls,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageText(
            userName: '观众',
            message: message,
            imageUrls: imageUrls,
            userStyle: const TextStyle(fontSize: 14, color: Colors.grey),
            messageStyle: const TextStyle(fontSize: 14, color: Colors.black),
          ),
        ),
      ),
    );

    final root = tester
        .widgetList<Text>(find.byType(Text))
        .firstWhere((text) => text.textSpan != null)
        .textSpan! as TextSpan;
    return root;
  }

  List<String> imageUrlsOf(TextSpan root) {
    final urls = <String>[];
    for (final span in root.children ?? const <InlineSpan>[]) {
      if (span is WidgetSpan && span.child is NetImage) {
        urls.add((span.child as NetImage).picUrl);
      }
    }
    return urls;
  }

  int widgetSpanCount(TextSpan root) =>
      (root.children ?? const <InlineSpan>[]).whereType<WidgetSpan>().length;

  String plainTextOf(TextSpan root) =>
      root.toPlainText(includePlaceholders: false);

  testWidgets('repeated token reuses the single de-duplicated url', (
    tester,
  ) async {
    final root = await pumpMessage(
      tester,
      message: '[奸笑]' * 20,
      imageUrls: const ['https://cdn.test/jianxiao.png'],
    );

    expect(widgetSpanCount(root), 20);
    expect(
      imageUrlsOf(root).every((url) => url == 'https://cdn.test/jianxiao.png'),
      isTrue,
    );
    expect(
      plainTextOf(root),
      '观众：',
      reason: '20 次重复表情都应变成图片，不能残留字面量 [奸笑]',
    );
  });

  testWidgets('distinct tokens keep distinct urls while repeats reuse them', (
    tester,
  ) async {
    final root = await pumpMessage(
      tester,
      message: '[笑][哭][笑][哭][笑]',
      imageUrls: const [
        'https://cdn.test/xiao.png',
        'https://cdn.test/ku.png',
      ],
    );

    expect(widgetSpanCount(root), 5);
    expect(imageUrlsOf(root), const [
      'https://cdn.test/xiao.png',
      'https://cdn.test/ku.png',
      'https://cdn.test/xiao.png',
      'https://cdn.test/ku.png',
      'https://cdn.test/xiao.png',
    ]);
    expect(plainTextOf(root), '观众：');
  });

  testWidgets('text around and between tokens is preserved verbatim', (
    tester,
  ) async {
    final root = await pumpMessage(
      tester,
      message: '前面[奸笑]中间[奸笑]后面',
      imageUrls: const ['https://cdn.test/jianxiao.png'],
    );

    expect(widgetSpanCount(root), 2);
    expect(plainTextOf(root), '观众：前面中间后面');
  });

  testWidgets('positionally aligned counts keep the legacy pairing', (
    tester,
  ) async {
    final root = await pumpMessage(
      tester,
      message: '[a][b]尾字',
      imageUrls: const [
        'https://cdn.test/1.png',
        'https://cdn.test/2.png',
      ],
    );

    expect(imageUrlsOf(root), const [
      'https://cdn.test/1.png',
      'https://cdn.test/2.png',
    ]);
    expect(plainTextOf(root), '观众：尾字');
  });

  testWidgets('leftover urls without tokens are still appended', (
    tester,
  ) async {
    final root = await pumpMessage(
      tester,
      message: '只有一个[笑]',
      imageUrls: const [
        'https://cdn.test/xiao.png',
        'https://cdn.test/extra.png',
      ],
    );

    expect(imageUrlsOf(root), const [
      'https://cdn.test/xiao.png',
      'https://cdn.test/extra.png',
    ]);
    expect(plainTextOf(root), '观众：只有一个');
  });

  testWidgets('de-duplicated repeats leave unused urls to be appended', (
    tester,
  ) async {
    final root = await pumpMessage(
      tester,
      message: '[笑][笑][笑]',
      imageUrls: const [
        'https://cdn.test/xiao.png',
        'https://cdn.test/extra.png',
      ],
    );

    expect(imageUrlsOf(root), const [
      'https://cdn.test/xiao.png',
      'https://cdn.test/xiao.png',
      'https://cdn.test/xiao.png',
      'https://cdn.test/extra.png',
    ]);
    expect(plainTextOf(root), '观众：');
  });

  testWidgets('tokens beyond the available urls stay literal text', (
    tester,
  ) async {
    final root = await pumpMessage(
      tester,
      message: '[a][b][c]',
      imageUrls: const ['https://cdn.test/1.png'],
    );

    expect(widgetSpanCount(root), 1);
    expect(plainTextOf(root), '观众：[b][c]');
  });

  testWidgets('empty imageUrls renders the message as plain text', (
    tester,
  ) async {
    final root = await pumpMessage(
      tester,
      message: '[奸笑][奸笑]纯文本',
      imageUrls: const [],
    );

    expect(widgetSpanCount(root), 0);
    expect(plainTextOf(root), '观众：[奸笑][奸笑]纯文本');
  });
}
