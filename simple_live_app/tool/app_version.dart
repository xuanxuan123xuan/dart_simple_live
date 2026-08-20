import 'dart:io';

final class AppVersion {
  const AppVersion({
    required this.name,
    required this.buildNumber,
    required this.updateChannel,
  });

  final String name;
  final int buildNumber;
  final String updateChannel;

  String get full => '$name+$buildNumber';
}

void main(List<String> arguments) {
  try {
    final command = arguments.firstOrNull;
    final appRoot = File.fromUri(Platform.script).parent.parent;

    if (command == 'set') {
      if (arguments.length != 2) {
        throw const FormatException(
          'Usage: dart run tool/app_version.dart set major.minor[.patch]',
        );
      }
      final version = _parseVersionName(arguments[1]);
      _set(appRoot, version);
      stdout.writeln('Set and synchronized app version ${version.full}.');
      return;
    }

    final version = _readVersion(File('${appRoot.path}/pubspec.yaml'));
    final updateChannel = _readUpdateChannel(appRoot);

    switch (command) {
      case 'sync':
        _sync(appRoot, version, updateChannel);
        stdout.writeln('Synchronized app version ${version.full}.');
        return;
      case 'check':
        _check(appRoot, version, updateChannel);
        stdout.writeln('App version ${version.full} is synchronized.');
        return;
      case 'print':
        stdout.writeln(_printValue(version, arguments.skip(1).toList()));
        return;
      default:
        throw const FormatException(
          'Usage: dart run tool/app_version.dart '
          '<set major.minor[.patch]|sync|check|'
          'print [name|build-number|full]>',
        );
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 74;
  }
}

AppVersion _parseVersionName(String value) {
  final match = RegExp(
    r'^[vV]?([0-9]+)\.([0-9]+)(?:\.([0-9]+))?$',
  ).firstMatch(value.trim());
  if (match == null) {
    throw const FormatException(
      'Version must use major.minor or major.minor.patch, '
      'for example 1.13 or 1.13.1.',
    );
  }
  return _versionFromComponents(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3) ?? '0'),
  );
}

AppVersion _readVersion(File pubspec) {
  final contents = pubspec.readAsStringSync();
  final match = RegExp(
    r'^version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)\s*$',
    multiLine: true,
  ).firstMatch(contents);
  if (match == null) {
    throw const FormatException(
      'pubspec.yaml must contain version: major.minor.patch+buildNumber.',
    );
  }

  final major = int.parse(match.group(1)!);
  final minor = int.parse(match.group(2)!);
  final patch = int.parse(match.group(3)!);
  final buildNumber = int.parse(match.group(4)!);
  final version = _versionFromComponents(major, minor, patch);
  if (buildNumber != version.buildNumber) {
    throw FormatException(
      'Invalid build number $buildNumber: '
      '${version.name} requires ${version.buildNumber}.',
    );
  }
  return version;
}

AppVersion _versionFromComponents(int major, int minor, int patch) {
  if (minor > 99 || patch > 99) {
    throw const FormatException(
      'Version minor and patch components must each be between 0 and 99.',
    );
  }

  final expectedBuildNumber = major * 10000 + minor * 100 + patch;
  return AppVersion(
    name: '$major.$minor.$patch',
    buildNumber: expectedBuildNumber,
    updateChannel: 'stable',
  );
}

String _readUpdateChannel(Directory appRoot) {
  final envChannel = Platform.environment['APP_UPDATE_CHANNEL']?.trim();
  if (envChannel == 'dev' || envChannel == 'stable') {
    return envChannel!;
  }

  final refName = Platform.environment['GITHUB_REF_NAME']?.trim();
  if (refName == 'dev' || refName == 'stable') {
    return refName!;
  }

  try {
    final result = Process.runSync(
      'git',
      ['branch', '--show-current'],
      workingDirectory: appRoot.path,
    );
    if (result.exitCode == 0) {
      final branch = (result.stdout as String).trim();
      if (branch == 'dev' || branch == 'stable') {
        return branch;
      }
    }
  } catch (_) {
    // Fall through to the default below.
  }

  return 'stable';
}

void _set(Directory appRoot, AppVersion version) {
  final pubspec = File('${appRoot.path}/pubspec.yaml');
  final contents = pubspec.readAsStringSync();
  final pattern = RegExp(r'^version:\s*[^\r\n]+$', multiLine: true);
  if (!pattern.hasMatch(contents)) {
    throw const FormatException('pubspec.yaml must contain a version field.');
  }
  final updated = contents.replaceFirst(pattern, 'version: ${version.full}');
  if (updated != contents) {
    pubspec.writeAsStringSync(updated);
  }
  _sync(appRoot, version, _readUpdateChannel(appRoot));
}

void _sync(Directory appRoot, AppVersion version, String updateChannel) {
  final ohosManifest = File('${appRoot.path}/ohos/AppScope/app.json5');
  final manifestContents = ohosManifest.readAsStringSync();
  final updatedManifest = _updatedOhosManifest(manifestContents, version);
  if (updatedManifest != manifestContents) {
    ohosManifest.writeAsStringSync(updatedManifest);
  }

  final generatedFile = File(_generatedVersionPath(appRoot));
  final generatedContents = _generatedVersionContents(version);
  if (!generatedFile.existsSync() ||
      generatedFile.readAsStringSync() != generatedContents) {
    generatedFile.parent.createSync(recursive: true);
    generatedFile.writeAsStringSync(generatedContents);
  }

  final generatedChannelFile = File(_generatedUpdateChannelPath(appRoot));
  final generatedChannelContents = _generatedUpdateChannelContents(updateChannel);
  if (!generatedChannelFile.existsSync() ||
      generatedChannelFile.readAsStringSync() != generatedChannelContents) {
    generatedChannelFile.parent.createSync(recursive: true);
    generatedChannelFile.writeAsStringSync(generatedChannelContents);
  }
}

void _check(Directory appRoot, AppVersion version, String updateChannel) {
  final problems = <String>[];
  final ohosManifest = File('${appRoot.path}/ohos/AppScope/app.json5');
  final manifestContents = ohosManifest.readAsStringSync();
  if (_updatedOhosManifest(manifestContents, version) != manifestContents) {
    problems.add('ohos/AppScope/app.json5');
  }

  final generatedFile = File(_generatedVersionPath(appRoot));
  if (!generatedFile.existsSync() ||
      generatedFile.readAsStringSync() != _generatedVersionContents(version)) {
    problems.add('lib/generated/app_version.g.dart');
  }

  final generatedChannelFile = File(_generatedUpdateChannelPath(appRoot));
  if (!generatedChannelFile.existsSync() ||
      generatedChannelFile.readAsStringSync() !=
          _generatedUpdateChannelContents(updateChannel)) {
    problems.add('lib/generated/app_update_channel.g.dart');
  }

  if (problems.isNotEmpty) {
    throw FormatException(
      'Version files are out of date: ${problems.join(', ')}. '
      'Run dart run tool/app_version.dart sync.',
    );
  }
}

String _updatedOhosManifest(String contents, AppVersion version) {
  final versionCodePattern = RegExp(r'("versionCode"\s*:\s*)[0-9]+');
  final versionNamePattern = RegExp(r'("versionName"\s*:\s*)"[^"]*"');
  if (!versionCodePattern.hasMatch(contents) ||
      !versionNamePattern.hasMatch(contents)) {
    throw const FormatException(
      'ohos/AppScope/app.json5 must contain versionCode and versionName.',
    );
  }

  return contents
      .replaceFirstMapped(
        versionCodePattern,
        (match) => '${match.group(1)}${version.buildNumber}',
      )
      .replaceFirstMapped(
        versionNamePattern,
        (match) => '${match.group(1)}"${version.name}"',
      );
}

String _generatedVersionPath(Directory appRoot) =>
    '${appRoot.path}/lib/generated/app_version.g.dart';

String _generatedVersionContents(AppVersion version) => '''
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by: dart run tool/app_version.dart sync

abstract final class GeneratedAppVersion {
  static const versionName = '${version.name}';
  static const buildNumber = '${version.buildNumber}';
  static const fullVersion = '${version.full}';
}
''';

String _generatedUpdateChannelPath(Directory appRoot) =>
    '${appRoot.path}/lib/generated/app_update_channel.g.dart';

String _generatedUpdateChannelContents(String updateChannel) => '''
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by: dart run tool/app_version.dart sync

abstract final class GeneratedAppUpdateChannel {
  static const channel = '$updateChannel';
  static const isDev = channel == 'dev';
}
''';

String _printValue(AppVersion version, List<String> arguments) {
  if (arguments.length > 1) {
    throw const FormatException('The print command accepts at most one field.');
  }
  return switch (arguments.firstOrNull ?? 'full') {
    'name' => version.name,
    'build-number' => version.buildNumber.toString(),
    'full' => version.full,
    final field => throw FormatException(
        'Unknown print field "$field". Use name, build-number, or full.',
      ),
  };
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
