import 'dart:io';

class KuaishouPrivateBrowserCandidate {
  const KuaishouPrivateBrowserCandidate(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

List<KuaishouPrivateBrowserCandidate> buildKuaishouPrivateBrowserCandidates({
  required String operatingSystem,
  required Map<String, String> environment,
  required String url,
}) {
  switch (operatingSystem) {
    case 'windows':
      final programFiles = _environmentValue(environment, 'PROGRAMFILES');
      final programFilesX86 =
          _environmentValue(environment, 'PROGRAMFILES(X86)');
      final localAppData = _environmentValue(environment, 'LOCALAPPDATA');
      return _deduplicateCandidates([
        if (programFilesX86 != null)
          KuaishouPrivateBrowserCandidate(
            _windowsPath(
              programFilesX86,
              r'Microsoft\Edge\Application\msedge.exe',
            ),
            ['--inprivate', '--new-window', url],
          ),
        if (programFiles != null)
          KuaishouPrivateBrowserCandidate(
            _windowsPath(
              programFiles,
              r'Google\Chrome\Application\chrome.exe',
            ),
            ['--incognito', '--new-window', url],
          ),
        if (programFilesX86 != null)
          KuaishouPrivateBrowserCandidate(
            _windowsPath(
              programFilesX86,
              r'Google\Chrome\Application\chrome.exe',
            ),
            ['--incognito', '--new-window', url],
          ),
        if (localAppData != null)
          KuaishouPrivateBrowserCandidate(
            _windowsPath(
              localAppData,
              r'Google\Chrome\Application\chrome.exe',
            ),
            ['--incognito', '--new-window', url],
          ),
        if (programFiles != null)
          KuaishouPrivateBrowserCandidate(
            _windowsPath(
              programFiles,
              r'Mozilla Firefox\firefox.exe',
            ),
            ['-private-window', url],
          ),
        KuaishouPrivateBrowserCandidate(
          'msedge.exe',
          ['--inprivate', '--new-window', url],
        ),
        KuaishouPrivateBrowserCandidate(
          'chrome.exe',
          ['--incognito', '--new-window', url],
        ),
        KuaishouPrivateBrowserCandidate(
          'firefox.exe',
          ['-private-window', url],
        ),
      ]);
    case 'macos':
      return [
        KuaishouPrivateBrowserCandidate(
          '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
          ['--incognito', '--new-window', url],
        ),
        KuaishouPrivateBrowserCandidate(
          '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
          ['--inprivate', '--new-window', url],
        ),
        KuaishouPrivateBrowserCandidate(
          '/Applications/Firefox.app/Contents/MacOS/firefox',
          ['-private-window', url],
        ),
      ];
    case 'linux':
      return [
        KuaishouPrivateBrowserCandidate(
          'google-chrome',
          ['--incognito', '--new-window', url],
        ),
        KuaishouPrivateBrowserCandidate(
          'chromium',
          ['--incognito', '--new-window', url],
        ),
        KuaishouPrivateBrowserCandidate(
          'chromium-browser',
          ['--incognito', '--new-window', url],
        ),
        KuaishouPrivateBrowserCandidate(
          'microsoft-edge',
          ['--inprivate', '--new-window', url],
        ),
        KuaishouPrivateBrowserCandidate(
          'firefox',
          ['-private-window', url],
        ),
      ];
    default:
      return const [];
  }
}

class KuaishouPrivateBrowserLauncher {
  const KuaishouPrivateBrowserLauncher._();

  static Future<bool> open(String url) async {
    final candidates = buildKuaishouPrivateBrowserCandidates(
      operatingSystem: Platform.operatingSystem,
      environment: Platform.environment,
      url: url,
    );
    for (final candidate in candidates) {
      try {
        await Process.start(
          candidate.executable,
          candidate.arguments,
          mode: ProcessStartMode.detached,
        );
        return true;
      } on ProcessException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    return false;
  }
}

String? _environmentValue(Map<String, String> environment, String name) {
  final normalizedName = name.toUpperCase();
  for (final entry in environment.entries) {
    if (entry.key.toUpperCase() == normalizedName && entry.value.isNotEmpty) {
      return entry.value;
    }
  }
  return null;
}

String _windowsPath(String root, String child) {
  final separator = root.endsWith(r'\') ? '' : r'\';
  return '$root$separator$child';
}

List<KuaishouPrivateBrowserCandidate> _deduplicateCandidates(
  List<KuaishouPrivateBrowserCandidate> candidates,
) {
  final seen = <String>{};
  return candidates
      .where((candidate) => seen.add(candidate.executable.toLowerCase()))
      .toList(growable: false);
}
