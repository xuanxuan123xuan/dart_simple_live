import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/live_link_health_media_kit_adapter.dart';
import 'package:simple_live_app/services/live_link_health_models.dart';

void main() {
  test('converts an exact MPV AO underrun log into a structured event', () {
    expect(
      classifyMpvLiveLinkLog(
        prefix: 'ao/wasapi',
        text: 'Audio device underrun detected.',
      ),
      LiveLinkEventType.audioUnderrun,
    );
  });

  test('does not classify unrelated or non-AO log messages', () {
    expect(
      classifyMpvLiveLinkLog(
        prefix: 'cplayer',
        text: 'Audio device underrun detected.',
      ),
      isNull,
    );
    expect(
      classifyMpvLiveLinkLog(
        prefix: 'ao',
        text: 'Audio buffer is low',
      ),
      isNull,
    );
  });
}
