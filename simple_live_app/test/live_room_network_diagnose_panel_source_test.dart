import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual diagnosis presents the current live-link health snapshot', () {
    final panel = _quickAccessPanelSource();

    expect(panel, contains('currentLiveLinkHealthSnapshot'));
    expect(panel, contains('currentLiveLinkHealthBuffering'));
    expect(panel, contains('presentLiveLinkHealthSnapshot'));
    expect(panel, contains('_buildHealthSection()'));
  });

  test('diagnosis stays inside the quick-access container', () {
    final controls = File(
      'lib/modules/live_room/player/player_controls.dart',
    ).readAsStringSync();
    final room = File(
      'lib/modules/live_room/live_room_page.dart',
    ).readAsStringSync();
    final panel = _quickAccessPanelSource();

    expect(controls, contains('LiveRoomQuickAccessPanel('));
    expect(panel, contains('AnimatedSwitcher('));
    expect(panel, contains('PopScope('));
    expect(panel, contains('_buildDiagnosticsPage()'));
    expect(panel, contains('readPlaybackDiagnosticRows()'));
    expect(room, contains('openDiagnostics: true'));
    expect(room, isNot(contains('void _showDiagnosticsMenu()')));
    expect(room, isNot(contains('void showNetworkDiagnose(')));
  });

  test('network diagnosis is configurable and disabled by default', () {
    final constants = File('lib/app/constant.dart').readAsStringSync();
    final settings = File(
      'lib/app/controller/app_settings_controller.dart',
    ).readAsStringSync();

    expect(constants, contains('"contribution_rank"'));
    expect(constants, contains('"network_diagnostics"'));
    expect(settings, contains('key != "network_diagnostics"'));
  });
}

String _quickAccessPanelSource() => File(
      'lib/modules/live_room/widgets/live_room_quick_access_panel.dart',
    ).readAsStringSync();
