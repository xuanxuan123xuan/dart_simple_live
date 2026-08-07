import 'package:simple_live_core/src/common/kuaishou_cooldown_evidence_tracker.dart';
import 'package:test/test.dart';

void main() {
  group('KuaishouCooldownEvidenceTracker authentication detection', () {
    test('does not treat anonymous or device-only cookies as logged in', () {
      expect(
        KuaishouCooldownEvidenceTracker.hasAuthenticatedSession(''),
        isFalse,
      );
      expect(
        KuaishouCooldownEvidenceTracker.hasAuthenticatedSession(
          'did=device-id; kpf=PC_WEB; kwfv1=client-value',
        ),
        isFalse,
      );
      expect(
        KuaishouCooldownEvidenceTracker.hasAuthenticatedSession(
          'did=device-id; kuaishou.live.web_st=login-token',
        ),
        isTrue,
      );
    });
  });

  group('KuaishouCooldownEvidenceTracker credential evidence', () {
    test('anonymous 403 is classification-only', () {
      final tracker = KuaishouCooldownEvidenceTracker();

      expect(
        tracker.recordCredentialRejection(
          endpoint: 'room_page',
          sessionEpoch: 1,
          hasAuthenticatedSession: false,
        ),
        isFalse,
      );
      expect(
        tracker.recordCredentialRejection(
          endpoint: 'room_page',
          sessionEpoch: 1,
          hasAuthenticatedSession: false,
        ),
        isFalse,
      );
    });

    test('first authenticated 403 is evidence and second starts cooldown', () {
      final tracker = KuaishouCooldownEvidenceTracker();

      expect(
        tracker.recordCredentialRejection(
          endpoint: 'room_page',
          sessionEpoch: 1,
          hasAuthenticatedSession: true,
        ),
        isFalse,
      );
      expect(
        tracker.recordCredentialRejection(
          endpoint: 'room_page',
          sessionEpoch: 1,
          hasAuthenticatedSession: true,
        ),
        isTrue,
      );
      expect(
        tracker.recordCredentialRejection(
          endpoint: 'room_page',
          sessionEpoch: 1,
          hasAuthenticatedSession: true,
        ),
        isFalse,
      );
    });

    test('endpoints and session epochs do not share evidence', () {
      final tracker = KuaishouCooldownEvidenceTracker();

      expect(
        tracker.recordCredentialRejection(
          endpoint: 'room_page',
          sessionEpoch: 1,
          hasAuthenticatedSession: true,
        ),
        isFalse,
      );
      expect(
        tracker.recordCredentialRejection(
          endpoint: 'websocket_info',
          sessionEpoch: 1,
          hasAuthenticatedSession: true,
        ),
        isFalse,
      );
      expect(
        tracker.recordCredentialRejection(
          endpoint: 'room_page',
          sessionEpoch: 2,
          hasAuthenticatedSession: true,
        ),
        isFalse,
      );
      expect(
        tracker.recordCredentialRejection(
          endpoint: 'room_page',
          sessionEpoch: 1,
          hasAuthenticatedSession: true,
        ),
        isTrue,
      );
    });

    test('successful response and reset clear accumulated evidence', () {
      final tracker = KuaishouCooldownEvidenceTracker();

      expect(
        tracker.recordCredentialRejection(
          endpoint: 'room_page',
          sessionEpoch: 1,
          hasAuthenticatedSession: true,
        ),
        isFalse,
      );
      tracker.recordSuccess(endpoint: 'room_page', sessionEpoch: 1);
      expect(
        tracker.recordCredentialRejection(
          endpoint: 'room_page',
          sessionEpoch: 1,
          hasAuthenticatedSession: true,
        ),
        isFalse,
      );
      tracker.reset();
      expect(
        tracker.recordCredentialRejection(
          endpoint: 'room_page',
          sessionEpoch: 1,
          hasAuthenticatedSession: true,
        ),
        isFalse,
      );
    });
  });

  test('429 requests immediate global cooldown', () {
    expect(
      KuaishouCooldownEvidenceTracker.immediateCooldownForStatus(429),
      KuaishouCooldownEvidenceTracker.rateLimitCooldownDuration,
    );
    expect(
      KuaishouCooldownEvidenceTracker.immediateCooldownForStatus(403),
      isNull,
    );
  });
}
