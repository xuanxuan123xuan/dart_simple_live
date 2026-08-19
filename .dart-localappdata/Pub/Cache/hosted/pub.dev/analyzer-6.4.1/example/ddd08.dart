// import 'dart:developer' as developer;
// import 'dart:io' as io;
// import 'dart:typed_data';
//
// import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
// import 'package:analyzer/src/dart/analysis/byte_store.dart';
// import 'package:heap_snapshot/analysis.dart';
// import 'package:heap_snapshot/format.dart';
// import 'package:vm_service/vm_service.dart';
//
// import '../tool/benchmark/heap/result.dart';
//
// void main() async {
//   final byteStore = MemoryByteStore();
//
//   for (var i = 0; i < 3; i++) {
//     final collection = AnalysisContextCollectionImpl(
//       includedPaths: [
//         // '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analysis_server',
//         '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analyzer',
//       ],
//       byteStore: byteStore,
//       drainStreams: false,
//     );
//
//     for (var j = 0; j < 10; j++) {
//       final timer = Stopwatch()..start();
//       for (final analysisContext in collection.contexts) {
//         var analysisDriver = analysisContext.driver;
//         var files = await analysisDriver.getFilesReferencingName('knownFiles');
//       }
//       // print('[$i][$j][time: ${timer.elapsedMilliseconds} ms]');
//       print('[$i][$j][time: ${timer.elapsedMicroseconds} mcs]');
//     }
//
//     {
//       var bytes = _getHeapSnapshot();
//       _analyzeSnapshot(bytes);
//     }
//
//     await collection.dispose();
//   }
// }
//
// void _analyzeSnapshot(Uint8List bytes) {
//   final allResults = BenchmarkResultCompound(
//     name: 'benchmark',
//   );
//
//   final graph = HeapSnapshotGraph.fromChunks(
//       [bytes.buffer.asByteData(bytes.offsetInBytes, bytes.length)]);
//
//   final analysis = Analysis(graph);
//
//   // Computing reachable objects takes some time.
//   analysis.reachableObjects;
//   {
//     final measure = analysis.measureObjects(analysis.reachableObjects);
//     allResults.add(
//       BenchmarkResultCompound(name: 'reachableObjects', children: [
//         BenchmarkResultCount(
//           name: 'count',
//           value: measure.count,
//         ),
//         BenchmarkResultBytes(
//           name: 'size',
//           value: measure.size,
//         ),
//       ]),
//     );
//   }
//
//   print(allResults.asDisplayText(null));
//
//   // It is interesting to see all reachable objects.
//   // {
//   //   print('Reachable objects');
//   //   final objects = analysis.reachableObjects;
//   //   analysis.printObjectStats(objects, maxLines: 100);
//   // }
// }
//
// Uint8List _getHeapSnapshot() {
//   final tmpDir = io.Directory.systemTemp.createTempSync('analyzer_heap');
//   try {
//     final snapshotFile = io.File('${tmpDir.path}/0.heap_snapshot');
//     developer.NativeRuntime.writeHeapSnapshotToFile(snapshotFile.path);
//     return snapshotFile.readAsBytesSync();
//   } finally {
//     tmpDir.deleteSync(recursive: true);
//   }
// }
//
// class _ObjectSetMeasure {
//   final int count;
//   final int size;
//
//   _ObjectSetMeasure({required this.count, required this.size});
// }
//
// extension on Analysis {
//   _ObjectSetMeasure measureObjects(IntSet objectIds) {
//     final stats = generateObjectStats(objectIds);
//     var totalSize = 0;
//     var totalCount = 0;
//     for (final class_ in stats.classes) {
//       totalCount += stats.counts[class_.classId];
//       totalSize += stats.sizes[class_.classId];
//     }
//     return _ObjectSetMeasure(count: totalCount, size: totalSize);
//   }
//
//   void printObjectStats(IntSet objectIds, {int maxLines = 20}) {
//     final stats = generateObjectStats(objectIds);
//     print(formatHeapStats(stats, maxLines: maxLines));
//     print('');
//   }
// }
