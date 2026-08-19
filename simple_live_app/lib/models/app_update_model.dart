import 'dart:convert';

enum AppUpdateChannel {
  stable,
  dev;

  String get label => switch (this) {
        AppUpdateChannel.stable => 'stable',
        AppUpdateChannel.dev => 'dev',
      };

  String get displayName => switch (this) {
        AppUpdateChannel.stable => '稳定版',
        AppUpdateChannel.dev => '开发版',
      };

  static AppUpdateChannel fromValue(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'dev' => AppUpdateChannel.dev,
      _ => AppUpdateChannel.stable,
    };
  }
}

enum AppUpdatePlatform {
  android,
  windows,
  linux,
  macos,
  ohos,
  tv;

  String get label => switch (this) {
        AppUpdatePlatform.android => 'Android',
        AppUpdatePlatform.windows => 'Windows',
        AppUpdatePlatform.linux => 'Linux',
        AppUpdatePlatform.macos => 'macOS',
        AppUpdatePlatform.ohos => 'HarmonyOS',
        AppUpdatePlatform.tv => 'Android TV',
      };

  static AppUpdatePlatform? fromAssetName(String name) {
    final lower = name.toLowerCase();
    if (lower.startsWith('simple-live-tv-')) {
      return AppUpdatePlatform.tv;
    }
    if (!lower.startsWith('simple-live-')) {
      return null;
    }
    if (lower.contains('-android-')) {
      return AppUpdatePlatform.android;
    }
    if (lower.contains('-windows.')) {
      return AppUpdatePlatform.windows;
    }
    if (lower.contains('-linux.')) {
      return AppUpdatePlatform.linux;
    }
    if (lower.contains('-macos.')) {
      return AppUpdatePlatform.macos;
    }
    if (lower.contains('-ohos-')) {
      return AppUpdatePlatform.ohos;
    }
    return null;
  }
}

enum AppUpdatePackageKind {
  apk,
  exe,
  zip,
  appImage,
  deb,
  dmg,
  hap,
  aab,
  ipa;

  String get label => switch (this) {
        AppUpdatePackageKind.apk => 'APK',
        AppUpdatePackageKind.exe => 'EXE',
        AppUpdatePackageKind.zip => 'ZIP',
        AppUpdatePackageKind.appImage => 'AppImage',
        AppUpdatePackageKind.deb => 'DEB',
        AppUpdatePackageKind.dmg => 'DMG',
        AppUpdatePackageKind.hap => 'HAP',
        AppUpdatePackageKind.aab => 'AAB',
        AppUpdatePackageKind.ipa => 'IPA',
      };

  static AppUpdatePackageKind? fromFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.exe')) return AppUpdatePackageKind.exe;
    if (lower.endsWith('.zip')) return AppUpdatePackageKind.zip;
    if (lower.endsWith('.appimage')) return AppUpdatePackageKind.appImage;
    if (lower.endsWith('.deb')) return AppUpdatePackageKind.deb;
    if (lower.endsWith('.dmg')) return AppUpdatePackageKind.dmg;
    if (lower.endsWith('.hap')) return AppUpdatePackageKind.hap;
    if (lower.endsWith('.apk')) return AppUpdatePackageKind.apk;
    if (lower.endsWith('.aab')) return AppUpdatePackageKind.aab;
    if (lower.endsWith('.ipa')) return AppUpdatePackageKind.ipa;
    return null;
  }
}

class AppUpdateAsset {
  const AppUpdateAsset({
    required this.name,
    required this.url,
    required this.platform,
    required this.kind,
    this.abi,
    this.size,
    this.sha256,
  });

  final String name;
  final String url;
  final AppUpdatePlatform platform;
  final AppUpdatePackageKind kind;
  final String? abi;
  final int? size;
  final String? sha256;

  String get displayName {
    final parts = <String>[platform.label, kind.label];
    if (abi != null && abi!.isNotEmpty) {
      parts.add(abi!);
    }
    return parts.join(' / ');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'url': url,
        'platform': platform.label,
        'kind': kind.label,
        'abi': abi,
        'size': size,
        'sha256': sha256,
      };

  @override
  String toString() => jsonEncode(toJson());
}

class AppUpdateRelease {
  const AppUpdateRelease({
    required this.channel,
    required this.tag,
    required this.version,
    required this.buildNumber,
    required this.publishedAt,
    required this.assets,
    required this.body,
    required this.releaseUrl,
  });

  final AppUpdateChannel channel;
  final String tag;
  final String version;
  final int buildNumber;
  final DateTime? publishedAt;
  final List<AppUpdateAsset> assets;
  final String body;
  final String releaseUrl;

  String get channelLabel => channel.displayName;
}

class AppUpdateSelection {
  const AppUpdateSelection({
    required this.platform,
    required this.packageKind,
    this.abi,
  });

  final AppUpdatePlatform platform;
  final AppUpdatePackageKind packageKind;
  final String? abi;

  String get key => abi == null || abi!.isEmpty
      ? '${platform.name}:${packageKind.name}'
      : '${platform.name}:${packageKind.name}:$abi';

  @override
  String toString() => key;
}

class AppUpdateCatalog {
  const AppUpdateCatalog({
    required this.stable,
    required this.dev,
  });

  final AppUpdateRelease? stable;
  final AppUpdateRelease? dev;

  AppUpdateRelease? releaseForChannel(AppUpdateChannel channel) =>
      switch (channel) {
        AppUpdateChannel.stable => stable,
        AppUpdateChannel.dev => dev,
      };
}
