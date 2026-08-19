import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/src/dart/analysis/byte_store.dart';

void main() async {
  final byteStore = MemoryByteStore();

  // {
  //   final collection = AnalysisContextCollectionImpl(
  //     includedPaths: [
  //       // '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analyzer',
  //       // '/Users/scheglov/Source/flutter/packages/flutter_tools',
  //       '/Users/scheglov/dart/20231112/augment_example',
  //     ],
  //     byteStore: byteStore,
  //   );
  //
  //   final timer = Stopwatch()..start();
  //   for (final analysisContext in collection.contexts) {
  //     print(analysisContext.contextRoot.root.path);
  //     final analysisSession = analysisContext.currentSession;
  //     for (final path in analysisContext.contextRoot.analyzedFiles()) {
  //       if (path.endsWith('.dart')) {
  //         print('  $path');
  //         await analysisSession.getUnitElement(path);
  //       }
  //     }
  //   }
  //   print('[time: ${timer.elapsedMilliseconds} ms]');
  // }

  {
    final collection = AnalysisContextCollectionImpl(
      includedPaths: [
        // '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analyzer',
        // '/Users/scheglov/Source/flutter/packages/flutter_tools',
        // '/Users/scheglov/dart/20231112/augment_example',
        // '/Users/scheglov/Source/Dart/sdk.git/sdk/tests/language/macros/augment',
        '/Users/scheglov/Source/Dart/sdk.git/sdk/tests/language/macros/json/json_serializable_test.dart',
      ],
      byteStore: byteStore,
    );

    final timer = Stopwatch()..start();
    for (final analysisContext in collection.contexts) {
      print(analysisContext.contextRoot.root.path);
      final analysisSession = analysisContext.currentSession;
      for (final path in analysisContext.contextRoot.analyzedFiles()) {
        if (path.endsWith('.dart')) {
          print('  $path');
          final libResult = await analysisSession.getResolvedLibrary(path);
          if (libResult is ResolvedLibraryResult) {
            for (final unitResult in libResult.units) {
              print('    ${unitResult.path}');
              print('      ${unitResult.errors}');
              print('---');
              print(unitResult.content);
              print('---');
            }
          }
        }
      }
    }
    print('[time: ${timer.elapsedMilliseconds} ms]');
    await collection.dispose();
  }
}
