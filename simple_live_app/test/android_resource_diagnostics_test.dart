import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/android_resource_diagnostics.dart';

void main() {
  test('formats fd and sync_file counts for support logs', () {
    expect(
      AndroidResourceDiagnostics.format(
        const AndroidResourceSnapshot(
          openFileDescriptors: 321,
          syncFileDescriptors: 87,
        ),
      ),
      '[android-resources] openFd=321 syncFile=87',
    );
  });
}
