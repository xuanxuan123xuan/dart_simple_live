import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_core/src/danmaku/douyin_mobile_emoji_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundles every Douyin mobile emoji asset', () async {
    final missingOrInvalid = <String>[];
    for (final assetUri in douyinMobileEmojiAssets.values.toSet()) {
      final assetPath = assetUri.substring('asset://'.length);
      try {
        final data = await rootBundle.load(assetPath);
        final bytes = data.buffer.asUint8List(data.offsetInBytes, 12);
        if (!_hasSupportedImageSignature(bytes)) {
          missingOrInvalid.add(assetPath);
        }
      } catch (_) {
        missingOrInvalid.add(assetPath);
      }
    }

    expect(
      missingOrInvalid,
      isEmpty,
      reason: 'Every mapped Douyin emoji must be a bundled PNG/WebP asset.',
    );
  });
}

bool _hasSupportedImageSignature(List<int> bytes) {
  const png = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  const riff = <int>[82, 73, 70, 70];
  const webp = <int>[87, 69, 66, 80];
  return _startsWith(bytes, png) ||
      (_startsWith(bytes, riff) && _matchesAt(bytes, webp, 8));
}

bool _startsWith(List<int> bytes, List<int> signature) =>
    _matchesAt(bytes, signature, 0);

bool _matchesAt(List<int> bytes, List<int> signature, int offset) {
  if (bytes.length < offset + signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[offset + i] != signature[i]) return false;
  }
  return true;
}
