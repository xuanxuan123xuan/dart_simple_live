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
    expect(panel, contains('_buildDiagnosticsPage()'));
    expect(panel, contains('readPlaybackDiagnosticRows()'));
    expect(room, contains('openDiagnostics: true'));
    expect(room, isNot(contains('void _showDiagnosticsMenu()')));
    expect(room, isNot(contains('void showNetworkDiagnose(')));
  });

  test('diagnosis opened as its own entry offers no quick-access back path',
      () {
    final panel = _quickAccessPanelSource();

    // 诊断页直接作为入口时（设置里的“网络诊断与播放信息”），左上角不能出现
    // 返回快捷入口的快捷键：返回路径以 initialDiagnostics 为条件。
    expect(
      panel,
      contains('_showDiagnostics && !widget.initialDiagnostics'),
    );
    expect(panel, contains('tooltip: canReturn ? "返回快捷入口" : "关闭"'));
    expect(panel, contains('if (canReturn && widget.isBottomSheet)'));
  });

  test('a pop closes the panel instead of stepping back to quick access', () {
    final panel = _quickAccessPanelSource();

    // 点击遮罩走 Navigator.maybePop，与系统返回同一条路径。面板一旦用 PopScope
    // 拦截 pop，遮罩点击就会被吞成“退回快捷入口”，容器关不掉。返回快捷入口只能
    // 由头部箭头显式触发。
    expect(panel, isNot(contains('PopScope')));
    expect(panel, isNot(contains('canPop')));
    expect(panel, isNot(contains('onPopInvokedWithResult')));
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
