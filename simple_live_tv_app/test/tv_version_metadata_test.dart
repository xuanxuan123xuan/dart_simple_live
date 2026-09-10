import '../lib/models/version_model.dart';

void main() {
  for (final tag in ['tv_v1.7.9', 'tv_v26.3.20-dev', 'tv_v1.7.9-pre']) {
    final value = VersionModel.fromJson({
      'download_url': 'https://github.com/example/repo/releases/tag/$tag',
      'version_num': '10709',
    });
    if (value.versionNum != 10709) throw StateError('Invalid build');
  }
  for (final url in [
    'https://github.com/example/repo/releases/tag/v1.7.9',
    'https://github.com/example/repo/releases/tag/v1.7.9-dev',
    '',
    'tv_v1.7.9',
  ]) {
    try {
      VersionModel.fromJson({'download_url': url});
    } on FormatException {
      continue;
    }
    throw StateError('Accepted invalid URL: $url');
  }
  print('TV metadata validation passed');
}
