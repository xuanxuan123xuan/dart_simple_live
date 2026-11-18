import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/routes/kuaishou_login_recommendation.dart';

void main() {
  test('only recommends login on the first anonymous Kuaishou entry', () {
    expect(
      KuaishouLoginRecommendation.shouldShow(
        isKuaishou: true,
        isAnonymous: true,
        hasBeenShown: false,
      ),
      isTrue,
    );
    expect(
      KuaishouLoginRecommendation.shouldShow(
        isKuaishou: true,
        isAnonymous: false,
        hasBeenShown: false,
      ),
      isFalse,
    );
    expect(
      KuaishouLoginRecommendation.shouldShow(
        isKuaishou: true,
        isAnonymous: true,
        hasBeenShown: true,
      ),
      isFalse,
    );
    expect(
      KuaishouLoginRecommendation.shouldShow(
        isKuaishou: false,
        isAnonymous: true,
        hasBeenShown: false,
      ),
      isFalse,
    );
  });

  test('recommends login when a configured account pool is currently anonymous',
      () {
    const primaryAccountConfigured = true;
    const activeSessionAvailable = false;

    expect(primaryAccountConfigured, isTrue);
    expect(
      KuaishouLoginRecommendation.shouldShow(
        isKuaishou: true,
        isAnonymous: !activeSessionAvailable,
        hasBeenShown: false,
      ),
      isTrue,
    );
  });

  test('copy explains anonymous viewing and login-only capabilities', () {
    expect(KuaishouLoginRecommendation.message, contains('游客'));
    expect(KuaishouLoginRecommendation.message, contains('公开直播'));
    expect(KuaishouLoginRecommendation.message, contains('弹幕'));
    expect(KuaishouLoginRecommendation.message, contains('关注'));
    expect(KuaishouLoginRecommendation.message, contains('账号'));
  });
}
