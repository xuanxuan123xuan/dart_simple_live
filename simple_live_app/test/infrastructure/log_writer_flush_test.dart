import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/log.dart';

void main() {
  test('flush waits for queued writes before a log file is exported', () async {
    final directory = await Directory.systemTemp.createTemp('simple-live-log-');
    final file = File('${directory.path}/diagnostic.log');
    final writer = LogFileWriter(sink: file.openWrite());
    Log.logFileWriter = writer;

    Log.writeLog('[android-video] {"event":"snapshot"}');
    await Log.flushWriter();
    await Log.disposeWriter();
    await writer.close();
    expect(await file.readAsString(), contains('[android-video]'));
    await directory.delete(recursive: true);
  });

  test('an early write, flush, and close wait for the file to open', () async {
    final directory = await Directory.systemTemp.createTemp('simple-live-log-');
    final opening = Completer<Directory>();
    final writer = LogFileWriter(
      fileName: 'early.log',
      supportDirectoryProvider: () => opening.future,
    );
    writer.write('before-open');
    final flushed = writer.flush();
    final closed = writer.close();
    opening.complete(directory);
    await flushed;
    await closed;
    expect(await File('${directory.path}/log/early.log').readAsString(),
        contains('before-open'));
    await directory.delete(recursive: true);
  });

  test('flush after close and rapid writer replacement stay ordered', () async {
    final directory = await Directory.systemTemp.createTemp('simple-live-log-');
    final oldFile = File('${directory.path}/old.log');
    final newFile = File('${directory.path}/new.log');
    final oldWriter = LogFileWriter(sink: oldFile.openWrite());
    Log.logFileWriter = oldWriter;
    Log.writeLog('old-run');
    final closingOld = Log.disposeWriter();

    final newWriter = LogFileWriter(sink: newFile.openWrite());
    Log.logFileWriter = newWriter;
    Log.writeLog('new-run');
    await Log.flushWriter();
    await closingOld;
    await Log.disposeWriter();
    expect(await oldFile.readAsString(), contains('old-run'));
    expect(await newFile.readAsString(), contains('new-run'));
    await directory.delete(recursive: true);
  });
}
