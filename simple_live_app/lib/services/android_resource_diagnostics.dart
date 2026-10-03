import 'dart:io';

class AndroidResourceSnapshot {
  const AndroidResourceSnapshot({
    required this.openFileDescriptors,
    required this.syncFileDescriptors,
  });

  final int openFileDescriptors;
  final int syncFileDescriptors;
}

class AndroidResourceDiagnostics {
  static AndroidResourceSnapshot? read() {
    if (!Platform.isAndroid) {
      return null;
    }
    try {
      var openFileDescriptors = 0;
      var syncFileDescriptors = 0;
      for (final entity in Directory('/proc/self/fd').listSync(
        followLinks: false,
      )) {
        openFileDescriptors += 1;
        if (entity is Link && entity.targetSync().contains('sync_file')) {
          syncFileDescriptors += 1;
        }
      }
      return AndroidResourceSnapshot(
        openFileDescriptors: openFileDescriptors,
        syncFileDescriptors: syncFileDescriptors,
      );
    } on FileSystemException {
      // The fd directory can change while it is being enumerated. A failed
      // sample must never affect playback or turn into a noisy error log.
      return null;
    }
  }

  static String format(AndroidResourceSnapshot snapshot) {
    return '[android-resources] '
        'openFd=${snapshot.openFileDescriptors} '
        'syncFile=${snapshot.syncFileDescriptors}';
  }
}
