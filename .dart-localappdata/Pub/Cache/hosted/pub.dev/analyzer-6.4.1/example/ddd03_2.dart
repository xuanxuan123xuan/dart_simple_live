// import 'dart:convert';
// import 'dart:io';
//
// import 'package:analyzer/file_system/physical_file_system.dart';
// import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
// import 'package:analyzer/src/dart/analysis/byte_store.dart';
// import 'package:analyzer/src/dart/analysis/file_content_cache.dart';
// import 'package:analyzer/src/dart/analysis/unlinked_unit_store.dart';
// import 'package:vm_service/vm_service.dart';
//
// import 'heap/analysis.dart';
// import 'heap/format.dart';
// import 'heap/load.dart';
//
// void main() async {
//   var path = '/Users/scheglov/dart/flutter_plugins/packages/camera';
//   // var path = '/Users/scheglov/dart/flutter_plugins/packages';
//
//   while (true) {
//     var resourceProvider = PhysicalResourceProvider.INSTANCE;
//     var fileContentCache = FileContentCache(resourceProvider);
//     var unlinkedUnitStore = UnlinkedUnitStoreImpl();
//
//     var collection = AnalysisContextCollectionImpl(
//       byteStore: MemoryByteStore(),
//       resourceProvider: resourceProvider,
//       fileContentCache: fileContentCache,
//       unlinkedUnitStore: unlinkedUnitStore,
//       sdkPath: '/Users/scheglov/Applications/dart-sdk',
//       // performanceLog: PerformanceLog(stdout),
//       includedPaths: [
//         path,
//       ],
//       // packagesFile:
//       //     '/Users/scheglov/dart/flutter_plugins/packages/camera/camera/.dart_tool/package_config.json',
//     );
//
//     // print('[Analysis contexts: ${collection.contexts.length}]');
//
//     var timer = Stopwatch()..start();
//     for (var analysisContext in collection.contexts) {
//       // print(analysisContext.contextRoot.root.path);
//       for (var filePath in analysisContext.contextRoot.analyzedFiles()) {
//         if (filePath.endsWith('.dart')) {
//           // print('  $filePath');
//           var analysisSession = analysisContext.currentSession;
//           await analysisSession.getResolvedUnit(filePath);
//         }
//       }
//     }
//     timer.stop();
//     print('[time: ${timer.elapsedMilliseconds} ms]');
//
//     {
//       var timer = Stopwatch()..start();
//       var chunks = await loadFromUri(Uri.parse('http://127.0.0.1:5000'));
//       // final length = chunks
//       //     .map((e) => e.lengthInBytes)
//       //     .fold<int>(0, (prev, e) => prev + e);
//       // print(
//       //   '  [${timer.elapsedMilliseconds} ms] '
//       //   'Downloaded heap snapshot, ${length / 1024 / 1024} MB.',
//       // );
//
//       final graph = HeapSnapshotGraph.fromChunks(chunks);
//       print('  [${timer.elapsedMilliseconds} ms] Created HeapSnapshotGraph.');
//       print('  externalSize: ${graph.externalSize}');
//       print('  shallowSize: ${graph.shallowSize}');
//       print('  Objects: ${graph.objects.length}');
//
//       final analysis = Analysis(graph);
//       print('  [${timer.elapsedMilliseconds} ms] Created Analysis.');
//
//       {
//         print('All objects.');
//         final objects = analysis.reachableObjects;
//         final stats = analysis.generateObjectStats(objects);
//         print(formatHeapStats(stats, maxLines: 20));
//         print('');
//       }
//
//       {
//         print('ElementImpl(s)');
//         var fileStateList = analysis.filter(
//           analysis.reachableObjects,
//           (object) {
//             return object.klass.name.endsWith('ElementImpl');
//           },
//         );
//         analysis.printObjectStats(fileStateList);
//         print('');
//         // final allObjects = analysis.transitiveGraph(fileStateList);
//         // analysis.printObjectStats(allObjects);
//         // print('');
//       }
//
//       {
//         print('Version(s)');
//         var objectList = analysis.filter(
//           analysis.reachableObjects,
//           (object) {
//             return object.klass.name == 'Version';
//           },
//         );
//         analysis.printObjectStats(objectList);
//         print('');
//         // final allObjects = analysis.transitiveGraph(fileStateList);
//         // analysis.printObjectStats(allObjects);
//         // print('');
//
//         const maxEntries = 10;
//         final paths = analysis.retainingPathsOf(objectList, 10);
//         for (int i = 0; i < paths.length; ++i) {
//           if (maxEntries != -1 && i >= maxEntries) break;
//           final path = paths[i];
//           print('There are ${path.count} retaining paths of');
//           print(formatRetainingPath(analysis.graph, paths[i]));
//           print('');
//         }
//       }
//     }
//   }
//
//   // var analysisContext = collection.contextFor(path);
//   // var unitResult = await analysisContext.currentSession.getResolvedUnit(path);
//   // unitResult as ResolvedUnitResult;
//
//   // await Future<void>.delayed(const Duration(days: 1));
// }
//
// extension on Analysis {
//   void printObjectStats(IntSet objectIds) {
//     final stats = generateObjectStats(objectIds);
//     print(formatHeapStats(stats, maxLines: 20));
//     print('');
//   }
//
//   void printRetainers(
//     IntSet objectIds, {
//     int maxEntries = 3,
//   }) {
//     final paths = retainingPathsOf(objectIds, 20);
//     for (int i = 0; i < paths.length; ++i) {
//       if (i >= maxEntries) break;
//       final path = paths[i];
//       print('There are ${path.count} retaining paths of');
//       print(formatRetainingPath(graph, paths[i]));
//       print('');
//     }
//   }
//
//   IntSet filterByClass(
//     IntSet objectIds, {
//     required Uri libraryUri,
//     required String name,
//   }) {
//     return filter(reachableObjects, (object) {
//       return object.klass.libraryUri == libraryUri && object.klass.name == name;
//     });
//   }
// }
