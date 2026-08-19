import 'dart:io' as io;

void main() {
  final file = io.File('/Users/scheglov/tmp/20230719_gc.txt');
  final lines = file.readAsStringSync().split('\n');
  final regExp = RegExp(r'^\[(.+?),(.+?),(.+?),(.+?),(.+?),');
  var totalDuration = Duration();
  for (final line in lines) {
    final match = regExp.firstMatch(line);
    if (match != null) {
      final singleDurationMsStr = match.group(5);
      if (singleDurationMsStr != null) {
        final milliSeconds = double.parse(singleDurationMsStr);
        final microSeconds = (milliSeconds * 1000).ceil();
        totalDuration += Duration(microseconds: microSeconds);
      }
    }
  }
  print('totalDuration: ${totalDuration.inMilliseconds} ms');
}
