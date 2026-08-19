import 'package:meta/meta.dart';
import 'package:html_unescape/html_unescape.dart' as all;
import 'package:html_unescape/html_unescape_small.dart' as small;

void main() {
  AllEntities().execute();
  // BasicEntities().execute();
}

class AllEntities extends Benchmark {
  final codec = all.HtmlUnescape();

  @override
  int run() {
    var result = codec.convert('&lt;strong&#62;This &quot;escaped&quot; string '
        'will be printed normally.</strong>');
    return result.codeUnitAt(0);
  }
}

class BasicEntities extends Benchmark {
  final codec = small.HtmlUnescape();

  @override
  int run() {
    var result = codec.convert('&lt;strong&#62;This &quot;escaped&quot; string '
        'will be printed normally.</strong>');
    return result.codeUnitAt(0);
  }
}

abstract class Benchmark {
  final int iterationsPerBatch = 100;

  final int batchesPerBenchmark = 5000;

  static const reportedBand = 95;

  final Stopwatch _watch = Stopwatch();

  void execute() {
    final measurements = _measure();
    // final lower = orderedValues[(batchesPerBenchmark * _outlierMargin).round()];
    // final upper = orderedValues[
    //     (batchesPerBenchmark - batchesPerBenchmark * _outlierMargin).round()];
    final mean = measurements.fold<double>(0, (total, a) => total + a) /
        measurements.length;
    final mad =
        measurements.fold<double>(0, (total, a) => total + (a - mean).abs()) /
            measurements.length;
    final lower = mean - mad;
    final upper = mean + mad;
    for (final m in measurements) {
      print('$m\t$lower\t$upper');
    }
  }

  void setup() {
    // Pass.
  }

  void tearDown() {
    // Pass.
  }

  int run();

  /// This exists so that the compiler cannot completely optimize-out the
  /// [run] function.
  @visibleForTesting
  int result = 0;

  /// Runs a batch of [iterationsPerBatch] executions of [run], and reports
  /// back the number of microseconds elapsed.
  int runBatch() {
    _watch.reset();
    _watch.start();
    for (var i = 0; i < iterationsPerBatch; i++) {
      result = run();
    }
    _watch.stop();
    return _watch.elapsedMicroseconds;
  }

  void warmup() {
    for (var i = 0; i < 3; i++) {
      runBatch();
    }
  }

  List<double> _measure() {
    final measurements = List<double>.generate(
        batchesPerBenchmark, (index) => -1,
        growable: false);
    warmup();
    for (var i = 0; i < batchesPerBenchmark; i++) {
      measurements[i] = runBatch() / iterationsPerBatch;
    }
    assert(!measurements.any((element) => element == -1));
    return measurements;
  }
}
