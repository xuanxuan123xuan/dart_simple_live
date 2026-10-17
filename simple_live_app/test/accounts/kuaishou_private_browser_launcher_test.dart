import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/kuaishou_private_browser_launcher.dart';

void main() {
  const url = 'https://live.kuaishou.com/';

  test('Windows candidates always request a new private window', () {
    final candidates = buildKuaishouPrivateBrowserCandidates(
      operatingSystem: 'windows',
      environment: const {
        'ProgramFiles': r'C:\Program Files',
        'ProgramFiles(x86)': r'C:\Program Files (x86)',
        'LocalAppData': r'C:\Users\tester\AppData\Local',
      },
      url: url,
    );

    expect(candidates, isNotEmpty);
    expect(
      candidates.every((candidate) => candidate.arguments.last == url),
      isTrue,
    );
    expect(
      candidates.every(
        (candidate) =>
            candidate.arguments.contains('--inprivate') ||
            candidate.arguments.contains('--incognito') ||
            candidate.arguments.contains('-private-window'),
      ),
      isTrue,
    );
  });

  test('macOS and Linux candidates never fall back to a normal window', () {
    for (final operatingSystem in const ['macos', 'linux']) {
      final candidates = buildKuaishouPrivateBrowserCandidates(
        operatingSystem: operatingSystem,
        environment: const {},
        url: url,
      );

      expect(candidates, isNotEmpty);
      expect(
        candidates.every(
          (candidate) =>
              candidate.arguments.contains('--inprivate') ||
              candidate.arguments.contains('--incognito') ||
              candidate.arguments.contains('-private-window'),
        ),
        isTrue,
      );
    }
  });

  test('unsupported systems produce no unsafe fallback candidate', () {
    expect(
      buildKuaishouPrivateBrowserCandidates(
        operatingSystem: 'unknown',
        environment: const {},
        url: url,
      ),
      isEmpty,
    );
  });
}
