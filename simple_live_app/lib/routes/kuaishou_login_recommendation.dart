class KuaishouLoginRecommendation {
  const KuaishouLoginRecommendation._();

  static const title = "登录快手账号";
  static const message = "您当前正在以游客身份观看。游客可观看公开直播；登录快手账号后，可使用弹幕互动、关注同步等账号相关功能。";

  static bool shouldShow({
    required bool isKuaishou,
    required bool isAnonymous,
    required bool hasBeenShown,
  }) {
    return isKuaishou && isAnonymous && !hasBeenShown;
  }
}
