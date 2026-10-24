import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/recordings/recordings_page.dart';
import 'package:simple_live_app/services/recording/recording_service.dart';

class _Backend implements RecordingBackend {
  @override
  Future<RecordingMediaInfo> probe(String path) async =>
      const RecordingMediaInfo(
          duration: Duration(seconds: 10),
          width: 320,
          height: 180,
          videoCodec: 'h264');
  @override
  Future<void> cancel() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PageService extends RecordingService {
  _PageService() : super(backend: _Backend());
  final entries = <RecordingSession>[];
  bool rejectSwitch = false;
  @override
  List<RecordingSession> get sessions => List.unmodifiable(entries);
  @override
  Future<void> initialize(String path) async {
    if (rejectSwitch && path.endsWith('another'))
      throw StateError('Recording is busy');
  }
}

void main() {
  late Directory root;
  late _PageService service;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('recordings-page-');
    service = _PageService();
  });
  tearDown(() async {
    await service.shutdown();
    service.dispose();
    await root.delete(recursive: true);
  });

  Widget app(RecordingsPage page) => MaterialApp(
      navigatorObservers: [FlutterSmartDialog.observer],
      builder: FlutterSmartDialog.init(),
      home: page);

  testWidgets('directory buttons remain disabled until loading finishes',
      (tester) async {
    final pending = Completer<Directory>();
    await tester.pumpWidget(app(RecordingsPage(
        service: service, resolveDirectory: () => pending.future)));
    expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.folder_open_outlined))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
            .onPressed,
        isNull);
    pending.complete(root);
    await tester.pumpAndSettle();
    expect(find.text('还没有录制内容'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.folder_open_outlined))
            .onPressed,
        isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed directory resolution can be retried from the page',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(app(RecordingsPage(
        service: service,
        resolveDirectory: () async {
          if (++attempts == 1)
            throw FileSystemException('temporarily unavailable');
          return root;
        })));
    await tester.pumpAndSettle();
    expect(find.textContaining('读取录制列表失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('还没有录制内容'), findsOneWidget);
    expect(attempts, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'rejected directory switch preserves preference and visible sessions',
      (tester) async {
    service.rejectSwitch = true;
    service.entries.add(RecordingSession(
        id: 'old',
        directory: root.path,
        roomId: '1',
        roomTitle: 'existing recording',
        platform: 'test',
        mode: RecordingMode.videoOnly,
        createdAt: DateTime(2026),
        status: RecordingStatus.queued));
    var saved = 0;
    await tester.pumpWidget(app(RecordingsPage(
      service: service,
      resolveDirectory: () async => root,
      chooseDirectory: () async => Directory('${root.path}/another'),
      rememberDirectory: (_) async {
        saved++;
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('existing recording'), findsOneWidget);
    await tester.tap(find.byTooltip('选择保存目录'));
    await tester.pumpAndSettle();
    expect(saved, 0);
    expect(find.text('existing recording'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await SmartDialog.dismiss();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}
