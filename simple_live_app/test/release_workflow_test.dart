import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  for (final file in [
    'release_all_platforms.yml',
    'release_tv.yml',
    'build_tvos_native.yml',
  ]) {
    test('$file parses and shell scripts have valid syntax', () async {
      final workflow =
          loadYaml(File('../.github/workflows/$file').readAsStringSync())
              as YamlMap;
      final jobs = workflow['jobs'] as YamlMap;
      for (final job in jobs.values.cast<YamlMap>()) {
        if (job['uses'] != null) continue;
        for (final step in (job['steps'] as YamlList).cast<YamlMap>()) {
          final script = step['run'];
          if (script is! String) continue;
          if (step['shell'] == 'pwsh' ||
              (step['shell'] == null &&
                  job['runs-on'].toString().contains('windows'))) continue;
          final bash = Platform.isWindows
              ? r'C:\Program Files\Git\bin\bash.exe'
              : 'bash';
          final process = await Process.start(bash, ['-n']);
          process.stdin.write(
              script.replaceAll(RegExp(r'\$\{\{.*?\}\}'), 'placeholder'));
          await process.stdin.close();
          expect(await process.exitCode, 0, reason: '$file: ${step['name']}');
        }
      }
      if (!jobs.containsKey('release')) return;
      final steps =
          (jobs['release']['steps'] as YamlList).cast<YamlMap>().toList();
      final notes = steps.firstWhere(
          (s) => s['run']?.toString().contains('release_notes.py') ?? false);
      expect(notes['run'], isNot(contains('sed -E')));
      if (file == 'release_tv.yml') {
        expect(jobs['tvos']['uses'], './.github/workflows/build_tvos_native.yml');
        expect(jobs['release']['needs'], contains('tvos'));
        expect(notes['run'], contains('-tvos-swift-unsigned.ipa'));
        final publish = steps
            .indexWhere((s) => s['uses'] == 'softprops/action-gh-release@v2');
        final sync =
            steps.indexWhere((s) => s['name'] == '同步 TV 版本元数据到 master');
        expect(sync, greaterThan(publish));
        expect(steps[sync]['if'], steps[publish]['if']);
        expect(steps[sync]['if'], isNot(contains('always()')));
        expect(jobs['release']['permissions']['contents'], 'write');
      }
    });
  }
}
