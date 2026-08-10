import 'dart:io';

import 'package:simple_live_core/simple_live_core.dart';

Future<void> main(List<String> args) async {
  final roomIds = args
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .take(3)
      .toList(growable: false);
  if (roomIds.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/kuaishou_session_diagnostic.dart <room> [room] [room]',
    );
    exitCode = 64;
    return;
  }

  final site = KuaishouSite();
  final cookie = Platform.environment['KS_TEST_COOKIE']?.trim() ?? '';
  if (cookie.isNotEmpty) {
    site.activateAccountSession(
      sessionKey: 'diagnostic',
      cookie: cookie,
      kww: Platform.environment['KS_TEST_KWW']?.trim() ?? '',
    );
  } else {
    site.activateAnonymousMode();
  }

  for (var index = 0; index < roomIds.length; index++) {
    try {
      final detail = await KuaishouRequestTrace.run(
        KuaishouRequestSource.userEnter,
        () => site.getRoomDetail(roomId: roomIds[index]),
        scopeId: 'kuaishou:diagnostic',
        forceNetwork: true,
      );
      final qualities = await site.getPlayQualites(detail: detail);
      stdout.writeln(
        'probe=${index + 1} status=${detail.resolvedLiveStatus.name} '
        'playable=${qualities.isNotEmpty} danmaku=${detail.danmakuData != null}',
      );
    } on CoreError catch (error) {
      stdout.writeln(
        'probe=${index + 1} failed kind=${error.kind.name} '
        'status=${error.statusCode}',
      );
      if (error.statusCode == 429) break;
    } on KuaishouCooldownError {
      stdout.writeln('probe=${index + 1} stopped=cooldown');
      break;
    } catch (error) {
      stdout.writeln(
        'probe=${index + 1} failed type=${error.runtimeType}',
      );
    }
  }
}
