import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

class CacheClearResult {
  const CacheClearResult({
    required this.clearedBytes,
    required this.failedEntries,
  });

  final int clearedBytes;
  final int failedEntries;
}

class CacheService {
  const CacheService._();

  static Future<int> getCacheSize() async {
    if (kIsWeb) {
      return 0;
    }
    return calculateDirectorySize(await getApplicationCacheDirectory());
  }

  static Future<CacheClearResult> clearCache() async {
    var clearedBytes = 0;
    var failedEntries = 0;

    if (!kIsWeb) {
      final cacheDirectory = await getApplicationCacheDirectory();
      final sizeBefore = await calculateDirectorySize(cacheDirectory);
      failedEntries = await clearDirectory(cacheDirectory);
      final sizeAfter = await calculateDirectorySize(cacheDirectory);
      clearedBytes = (sizeBefore - sizeAfter).clamp(0, sizeBefore);
    }

    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();

    return CacheClearResult(
      clearedBytes: clearedBytes,
      failedEntries: failedEntries,
    );
  }

  static Future<int> calculateDirectorySize(Directory directory) async {
    if (!await directory.exists()) {
      return 0;
    }

    var size = 0;
    await for (final entity
        in directory.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      try {
        size += await entity.length();
      } on FileSystemException {
        // A cache file can disappear while its size is being calculated.
      }
    }
    return size;
  }

  /// Deletes the contents of [directory], while keeping the cache root itself.
  /// Returns the number of entries that could not be removed.
  static Future<int> clearDirectory(Directory directory) async {
    if (!await directory.exists()) {
      return 0;
    }

    var failedEntries = 0;
    await for (final entity in directory.list(followLinks: false)) {
      try {
        await entity.delete(recursive: true);
      } on FileSystemException {
        failedEntries += 1;
      }
    }
    return failedEntries;
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }

    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unitIndex]}';
  }
}
