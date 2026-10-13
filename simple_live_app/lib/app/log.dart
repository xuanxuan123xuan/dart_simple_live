import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/utils.dart';

class Log {
  static LogFileWriter? logFileWriter;
  static Future<void>? _closingWriter;
  static void initWriter() {
    logFileWriter ??= LogFileWriter();
  }

  static Future<void> disposeWriter() async {
    final writer = logFileWriter;
    logFileWriter = null;
    if (writer == null) {
      await _closingWriter;
      return;
    }
    final previous = _closingWriter;
    final closing = () async {
      try {
        await previous;
      } catch (_) {
        // A failed old writer must not prevent this writer from closing.
      }
      await writer.close();
    }();
    _closingWriter = closing;
    try {
      await closing;
    } finally {
      if (identical(_closingWriter, closing)) _closingWriter = null;
    }
  }

  static Future<void> flushWriter() async {
    await _closingWriter;
    await logFileWriter?.flush();
  }

  static void writeLog(content, [Level level = Level.info]) {
    logFileWriter
        ?.write("[${level.name.toUpperCase()}] $_currentTime：$content");
  }

  static RxList<DebugLogModel> debugLogs = <DebugLogModel>[].obs;

  static void addDebugLog(String content, Color? color) {
    if (kReleaseMode) {
      return;
    }
    if (content.contains("请求响应")) {
      content = content.split("\n").join('\n💡 ');
    }
    try {
      debugLogs.insert(0, DebugLogModel(DateTime.now(), content, color: color));
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  static Logger logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.none,
    ),
  );

  static void d(String message, [bool writeFile = true]) {
    addDebugLog(message, Colors.orange);
    logger.d("${DateTime.now().toString()}\n$message");
    if (writeFile) {
      writeLog(message, Level.debug);
    }
  }

  static void i(String message, [bool writeFile = true]) {
    addDebugLog(message, Colors.blue);
    logger.i("${DateTime.now().toString()}\n$message");
    if (writeFile) {
      writeLog(message, Level.info);
    }
  }

  static void e(String message, StackTrace stackTrace,
      [bool writeFile = true]) {
    addDebugLog('$message\r\n\r\n$stackTrace', Colors.red);
    logger.e("${DateTime.now().toString()}\n$message", stackTrace: stackTrace);
    if (writeFile) {
      writeLog("$message\n$stackTrace", Level.error);
    }
  }

  static void w(String message, [bool writeFile = true]) {
    addDebugLog(message, Colors.pink);
    logger.w("${DateTime.now().toString()}\n$message");
    if (writeFile) {
      writeLog(message, Level.warning);
    }
  }

  static void logPrint(dynamic obj, [bool writeFile = true]) {
    addDebugLog(obj.toString(), Colors.red);
    if (writeFile) {
      writeLog(obj, Level.info);
    }
    //logger.e(obj.toString(), obj, obj?.stackTrace);
    if (kDebugMode) {
      print(obj);
    }
  }

  static String get _currentTime => Utils.timeFormat.format(DateTime.now());
}

class LogFileWriter {
  LogFileWriter({
    IOSink? sink,
    String? fileName,
    Future<Directory> Function()? supportDirectoryProvider,
  })  : fileName = fileName ??
            "${DateFormat("yyyy-MM-dd HH-mm-ss").format(DateTime.now())}.log",
        _supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory {
    if (sink != null) {
      fileWriter = sink;
      _ready = Future<void>.value();
    } else {
      _ready = _openFile();
      // Queue the header before callers can queue their first log line.
      unawaited(writeSystemInfo());
    }
  }

  final String fileName;
  final Future<Directory> Function() _supportDirectoryProvider;
  IOSink? fileWriter;
  late final Future<void> _ready;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closeFuture;
  bool _closing = false;

  Future<void> _openFile() async {
    final supportDir = await _supportDirectoryProvider();
    var logDir = Directory("${supportDir.path}/log");
    if (!await logDir.exists()) {
      await logDir.create();
    }
    final logFile = File("${logDir.path}/$fileName");
    fileWriter = logFile.openWrite(mode: FileMode.append);
  }

  void write(Object? content) {
    if (_closing) return;
    unawaited(_enqueue(() async {
      await _ready;
      final writer = fileWriter;
      if (writer == null) return;
      writer.write(content);
      writer.write("\r\n");
    }).then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    ));
  }

  Future<void> flush() {
    return _enqueue(() async {
      await _ready;
      await fileWriter?.flush();
    });
  }

  Future<void> close() {
    return _closeFuture ??= _close();
  }

  Future<void> _close() {
    _closing = true;
    return _enqueue(() async {
      try {
        await _ready;
      } catch (_) {
        // The logger can still be closed when the support directory is not
        // available (for example, during an early startup failure).
      }
      final writer = fileWriter;
      fileWriter = null;
      if (writer == null) return;
      try {
        await writer.flush();
      } finally {
        await writer.close();
      }
    });
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final operation = _tail.then((_) => action());
    _tail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> writeSystemInfo() async {
    write("System Info:");
    write("Current Time: ${DateTime.now()}");
    write("Platform: ${Platform.operatingSystem}");
    write("Version: ${Platform.operatingSystemVersion}");
    write("Local: ${Platform.localeName}");
    try {
      write(
          "App Version: ${Utils.packageInfo.version}+${Utils.packageInfo.buildNumber}");
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        write((await deviceInfo.androidInfo).data.toString());
      } else if (Platform.isIOS) {
        write((await deviceInfo.iosInfo).data.toString());
      } else if (Platform.isLinux) {
        write((await deviceInfo.linuxInfo).data.toString());
      } else if (Platform.isMacOS) {
        write((await deviceInfo.macOsInfo).data.toString());
      } else if (Platform.isWindows) {
        write((await deviceInfo.windowsInfo).data.toString());
      }
    } catch (error) {
      write("Device Info unavailable: ${error.runtimeType}");
    }
    write("End System Info");
  }
}

class DebugLogModel {
  final String content;
  final DateTime datetime;
  final Color? color;
  DebugLogModel(this.datetime, this.content, {this.color});
}
