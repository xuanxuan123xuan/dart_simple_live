import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';

void main() async {
  final collection = AnalysisContextCollectionImpl(includedPaths: [
    '/Users/scheglov/dart/test',
  ]);

  for (final analysisContext in collection.contexts) {
    // print(analysisContext.contextRoot.root.path);
    final analysisSession = analysisContext.currentSession;
    for (final path in analysisContext.contextRoot.analyzedFiles()) {
      if (path.endsWith('.dart')) {
        print('  $path');
        await analysisSession.getResolvedUnit(path);
      }
    }
  }
}
