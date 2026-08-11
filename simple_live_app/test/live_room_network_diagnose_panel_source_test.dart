import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual diagnosis presents the current live-link health snapshot', () {
    final panel = _networkDiagnosePanelSource();

    expect(panel, contains('currentLiveLinkHealthSnapshot'));
    expect(panel, contains('currentLiveLinkHealthBuffering'));
    expect(panel, contains('presentLiveLinkHealthSnapshot'));
    expect(panel, contains('_buildHealthSection()'));
  });

  test('diagnosis content is scrollable on short screens', () {
    final source = _liveRoomPageSource();
    final entryStart = source.indexOf('void showNetworkDiagnose');
    final entryEnd = source.indexOf('double _bottomSafeInset', entryStart);
    final entry = source.substring(entryStart, entryEnd);
    final scrollView = entry.indexOf('SingleChildScrollView(');
    final panel = entry.indexOf('_NetworkDiagnosePanel(', scrollView);

    expect(entryStart, greaterThanOrEqualTo(0));
    expect(scrollView, greaterThanOrEqualTo(0));
    expect(panel, greaterThan(scrollView));
  });
}

String _networkDiagnosePanelSource() {
  final source = _liveRoomPageSource();
  final start = source.indexOf('class _NetworkDiagnosePanelState');

  expect(start, greaterThanOrEqualTo(0));
  return source.substring(start);
}

String _liveRoomPageSource() => File(
      'lib/modules/live_room/live_room_page.dart',
    ).readAsStringSync();
