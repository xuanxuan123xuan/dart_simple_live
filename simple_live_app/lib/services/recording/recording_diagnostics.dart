import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Low-volume recording diagnostics, including failures before a session exists.
/// Each append closes and flushes its file, so logging owns no shutdown resource.
class RecordingDiagnostics {
  RecordingDiagnostics({
    Future<Directory> Function()? supportDirectoryProvider,
    this.maxFileBytes = 2 * 1024 * 1024,
  }) : _supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory;

  static RecordingDiagnostics instance = RecordingDiagnostics();
  static const fileName = 'recording.log';
  final Future<Directory> Function() _supportDirectoryProvider;
  final int maxFileBytes;
  Future<void> _tail = Future<void>.value();
  int _queued = 0;

  void write(String event,
      {Map<String, Object?> data = const {},
      Object? error,
      StackTrace? stackTrace}) {
    // A failing native recorder or slow disk must not grow an unbounded queue.
    if (_queued >= 128) return;
    String line;
    try {
      line = '${jsonEncode({
            'time': DateTime.now().toUtc().toIso8601String(),
            'pid': pid,
            'event': _safe(event),
            ...data.map((key, value) => MapEntry(key, _safe(value))),
            if (error != null) 'errorType': error.runtimeType.toString(),
            if (error != null) 'error': _safe(error),
            if (stackTrace != null) 'stack': _safe(stackTrace),
          })}\n';
    } on Object {
      return;
    }
    _queued++;
    _tail = _tail.then((_) async {
      final support = await _supportDirectoryProvider();
      final directory = Directory(p.join(support.path, 'log'));
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, fileName));
      if (await file.exists() &&
          await file.length() + utf8.encode(line).length > maxFileBytes) {
        final previous = File('${file.path}.previous.log');
        if (await previous.exists()) await previous.delete();
        await file.rename(previous.path);
      }
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    }).then<void>((_) {
      _queued--;
    }, onError: (Object _, StackTrace __) {
      // Diagnostic storage failure must never fail recording or escape a Future.
      // The next event retries directory discovery and writing.
      _queued--;
    });
  }

  Future<void> flush() => _tail;

  static Object? _safe(Object? value) {
    if (value == null || value is bool || value is int) return value;
    if (value is double && value.isFinite) return value;
    if (value is Iterable) return value.take(20).map(_safe).toList();
    var text = value.toString();
    // Native errors can echo signed stream URLs or HTTP headers. Keep command
    // stages and return codes without putting playback credentials in the log.
    text = text.replaceAll(
        RegExp(r'\b(?:https?|rtmps?|rtsps?)://\S+', caseSensitive: false),
        '<stream-url>');
    text = text.replaceAll(
        RegExp(r'(?:cookie|authorization)\s*[:=][^\r\n]*',
            caseSensitive: false),
        '<credentials>');
    return text.length <= 4096 ? text : '${text.substring(0, 4096)}<truncated>';
  }
}
