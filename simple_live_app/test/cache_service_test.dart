import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/cache_service.dart';

void main() {
  group('CacheService', () {
    late Directory cacheDirectory;

    setUp(() async {
      cacheDirectory = await Directory.systemTemp.createTemp(
        'simple_live_cache_test_',
      );
    });

    tearDown(() async {
      if (await cacheDirectory.exists()) {
        await cacheDirectory.delete(recursive: true);
      }
    });

    test('calculates nested cache file sizes', () async {
      await File('${cacheDirectory.path}/first.cache').writeAsBytes([1, 2, 3]);
      final nested = await Directory(
        '${cacheDirectory.path}/nested',
      ).create();
      await File('${nested.path}/second.cache').writeAsBytes([4, 5]);

      expect(await CacheService.calculateDirectorySize(cacheDirectory), 5);
    });

    test('clears contents but keeps the cache root', () async {
      await File('${cacheDirectory.path}/first.cache').writeAsBytes([1, 2, 3]);
      final nested = await Directory(
        '${cacheDirectory.path}/nested',
      ).create();
      await File('${nested.path}/second.cache').writeAsBytes([4, 5]);

      final failedEntries = await CacheService.clearDirectory(cacheDirectory);

      expect(failedEntries, 0);
      expect(await cacheDirectory.exists(), isTrue);
      expect(await cacheDirectory.list().isEmpty, isTrue);
    });

    test('formats cache sizes for display', () {
      expect(CacheService.formatBytes(0), '0 B');
      expect(CacheService.formatBytes(1024), '1.0 KB');
      expect(CacheService.formatBytes(1536), '1.5 KB');
      expect(CacheService.formatBytes(2 * 1024 * 1024), '2.0 MB');
    });
  });
}
