import 'dart:convert';
import 'dart:io';

const _requiredSamples = <String>{
  '[都市丽人]',
  '[猪猪]',
  '[尊嘟假嘟]',
  '[憨笑哪吒]',
};

void main(List<String> arguments) {
  final options = _parseOptions(arguments);
  final input = options['input'];
  final output = options['output'];
  final version = options['client-version'];
  final source = options['source'];
  final generatedAt = options['generated-at'];
  final expectedCount = int.tryParse(options['expected-count'] ?? '');
  if ([input, output, version, source, generatedAt].any(
        (value) => value == null || value.isEmpty,
      ) ||
      expectedCount == null ||
      expectedCount <= 0) {
    stderr.writeln(
      'Usage: dart run tool/generate_kuaishou_mobile_emoji.dart '
      '--input response.json --output output.dart '
      '--client-version 14.7.10.49551 '
      '--source https://api.example/rest/n/emotion/package/list/v2 '
      '--generated-at 2026-08-11T00:00:00+08:00 '
      '--expected-count 500',
    );
    exitCode = 64;
    return;
  }

  final decoded = jsonDecode(File(input!).readAsStringSync());
  if (decoded is Map && decoded['result'] is num && decoded['result'] != 1) {
    throw FormatException(
      'Kuaishou API failed: result=${decoded['result']}, '
      'error=${decoded['error_msg'] ?? decoded['error'] ?? 'unknown'}',
    );
  }
  final assets = collectKuaishouMobileEmojiAssets(decoded);
  if (assets.isEmpty) {
    throw const FormatException('No mobile emotion entries found');
  }
  final missing = _requiredSamples.difference(assets.keys.toSet());
  if (missing.isNotEmpty) {
    throw FormatException('Required samples missing: ${missing.join(', ')}');
  }
  if (assets.length != expectedCount) {
    throw FormatException(
      'Expected $expectedCount unique mobile emotions, found ${assets.length}',
    );
  }

  final buffer = StringBuffer()
    ..writeln('// Generated. Do not edit by hand.')
    ..writeln('// Kuaishou Android client: $version')
    ..writeln('// Source: $source')
    ..writeln('// Generated at: $generatedAt')
    ..writeln('library;')
    ..writeln()
    ..writeln('const String kuaishouMobileEmojiClientVersion =')
    ..writeln('    ${_dartString(version!)};')
    ..writeln('const String kuaishouMobileEmojiSource =')
    ..writeln('    ${_dartString(source!)};')
    ..writeln('const String kuaishouMobileEmojiGeneratedAt =')
    ..writeln('    ${_dartString(generatedAt!)};')
    ..writeln('const int kuaishouMobileEmojiAssetCount = $expectedCount;')
    ..writeln()
    ..writeln('const Map<String, String> kuaishouMobileEmojiAssets = {');
  for (final entry in assets.entries) {
    buffer
      ..writeln("  ${_dartString(entry.key)}:")
      ..writeln("      ${_dartString(entry.value)},");
  }
  buffer.writeln('};');
  File(output!).writeAsStringSync(buffer.toString());
  stdout.writeln('Generated ${assets.length} Kuaishou mobile emoji entries.');
}

Map<String, String> _parseOptions(List<String> arguments) {
  final result = <String, String>{};
  for (var index = 0; index < arguments.length; index += 1) {
    final argument = arguments[index];
    if (!argument.startsWith('--') || index + 1 >= arguments.length) {
      continue;
    }
    result[argument.substring(2)] = arguments[++index];
  }
  return result;
}

Map<String, String> collectKuaishouMobileEmojiAssets(Object? value) {
  final assets = <String, String>{};
  _visit(value, assets);
  return assets;
}

void _visit(Object? value, Map<String, String> assets) {
  if (value is List) {
    for (final item in value) {
      _visit(item, assets);
    }
    return;
  }
  if (value is! Map) return;

  final map = value.cast<Object?, Object?>();
  final codes = _readCodes(map['emotionCodes']);
  final url = _readUrl(map['emotionImageSmallUrl']) ??
      _readUrl(map['emotionImageBigUrl']) ??
      _readUrl(map['gifUrl']);
  if (url != null) {
    for (final token in codes) {
      if (!RegExp(r'^\[[^\[\]\r\n]{1,64}\]$').hasMatch(token)) continue;
      final existing = assets[token];
      if (existing != null) {
        if (existing == url) {
          continue;
        }
        // 同一 token 多处出现时采用先到先得，保持生成结果稳定；
        // 后续冲突项仅忽略，不覆盖已有映射。
        continue;
      }
      assets[token] = url;
    }
  }
  for (final child in map.values) {
    _visit(child, assets);
  }
}

Iterable<String> _readCodes(Object? value) sync* {
  if (value is! List) return;
  for (final item in value) {
    if (item is! Map) continue;
    for (final field in const ['codes', 'code']) {
      final codes = item[field];
      if (codes is List) {
        for (final code in codes.whereType<String>()) {
          final token = code.trim();
          if (token.isNotEmpty) yield token;
        }
      } else if (codes is String && codes.trim().isNotEmpty) {
        yield codes.trim();
      }
    }
  }
}

String? _readUrl(Object? value) {
  if (value is! List) return null;
  for (final item in value) {
    final raw = switch (item) {
      String() => item,
      Map() => item['url'] ?? item['mUrl'],
      _ => null,
    };
    if (raw is! String || raw.trim().isEmpty) continue;
    var url = raw.trim();
    if (url.startsWith('//')) url = 'https:$url';
    if (url.startsWith('http://')) url = 'https://${url.substring(7)}';
    final uri = Uri.tryParse(url);
    if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
      return uri.toString();
    }
  }
  return null;
}

String _dartString(String value) => jsonEncode(value);
