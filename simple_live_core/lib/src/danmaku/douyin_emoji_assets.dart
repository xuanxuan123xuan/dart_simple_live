// Generated from static Douyin emoji assets bundled with the apps.
// Source: https://www.emojiall.com/zh-hans/platform-douyin
//
// 内置表为打包快照（兜底，asset:// 本地图）；运行时可通过
// [refreshDouyinEmoji] 拉取抖音官方 emoji 接口并覆盖为 CDN 图，
// 抖音新增/变更表情无需发版。
library;

import 'dart:convert';

import 'package:simple_live_core/src/common/core_log.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/danmaku/douyin_mobile_emoji_assets.dart';
import 'package:simple_live_core/src/douyin_site.dart';
import 'package:simple_live_core/src/scripts/douyin_sign.dart';

const Map<String, String> douyinEmojiAssets = {
  '[V5]': 'asset://assets/images/douyin_emoji/clv.png',
  '[给力]': 'asset://assets/images/douyin_emoji/clw.png',
  '[嘿哈]': 'asset://assets/images/douyin_emoji/cm8.png',
  '[加好友]': 'asset://assets/images/douyin_emoji/cm9.png',
  '[勾引]': 'asset://assets/images/douyin_emoji/cmt.png',
  '[机智]': 'asset://assets/images/douyin_emoji/cn0.png',
  '[来看我]': 'asset://assets/images/douyin_emoji/cn1.png',
  '[灵机一动]': 'asset://assets/images/douyin_emoji/cn2.png',
  '[困]': 'asset://assets/images/douyin_emoji/cna.png',
  '[疑问]': 'asset://assets/images/douyin_emoji/cnb.png',
  '[泣不成声]': 'asset://assets/images/douyin_emoji/cnc.png',
  '[小鼓掌]': 'asset://assets/images/douyin_emoji/cnd.png',
  '[发呆]': 'asset://assets/images/douyin_emoji/cnf.png',
  '[吐血]': 'asset://assets/images/douyin_emoji/cnj.png',
  '[酷拽]': 'asset://assets/images/douyin_emoji/cnq.png',
  '[泪奔]': 'asset://assets/images/douyin_emoji/cnv.png',
  '[抠鼻]': 'asset://assets/images/douyin_emoji/co1.png',
  '[互粉]': 'asset://assets/images/douyin_emoji/co3.png',
  '[去污粉]': 'asset://assets/images/douyin_emoji/co8.png',
  '[666]': 'asset://assets/images/douyin_emoji/co9.png',
  '[舔屏]': 'asset://assets/images/douyin_emoji/cof.png',
  '[鄙视]': 'asset://assets/images/douyin_emoji/cog.png',
  '[紫薇别走]': 'asset://assets/images/douyin_emoji/coj.png',
  '[不失礼貌的微笑]': 'asset://assets/images/douyin_emoji/cop.png',
  '[吐舌]': 'asset://assets/images/douyin_emoji/coq.png',
  '[呆无辜]': 'asset://assets/images/douyin_emoji/cor.png',
  '[白眼]': 'asset://assets/images/douyin_emoji/cot.png',
  '[吃瓜群众]': 'asset://assets/images/douyin_emoji/cox.png',
  '[绿帽子]': 'asset://assets/images/douyin_emoji/coz.png',
  '[皱眉]': 'asset://assets/images/douyin_emoji/cp2.png',
  '[擦汗]': 'asset://assets/images/douyin_emoji/cp3.png',
  '[强]': 'asset://assets/images/douyin_emoji/cp7.png',
  '[如花]': 'asset://assets/images/douyin_emoji/cp8.png',
  '[奋斗]': 'asset://assets/images/douyin_emoji/cpc.png',
  '[微笑]': 'asset://assets/images/douyin_emoji/1f642.png',
  '[害羞]': 'asset://assets/images/douyin_emoji/1f60a.png',
  '[击掌]': 'asset://assets/images/douyin_emoji/1f64c.png',
  '[左上]': 'asset://assets/images/douyin_emoji/1f446.png',
  '[握手]': 'asset://assets/images/douyin_emoji/1f91d.png',
  '[18禁]': 'asset://assets/images/douyin_emoji/1f51e.png',
  '[菜刀]': 'asset://assets/images/douyin_emoji/1f52a.png',
  '[爱心]': 'asset://assets/images/douyin_emoji/2764.png',
  '[心碎]': 'asset://assets/images/douyin_emoji/1f494.png',
  '[便便]': 'asset://assets/images/douyin_emoji/1f4a9.png',
  '[惊讶]': 'asset://assets/images/douyin_emoji/1f632.png',
  '[调皮]': 'asset://assets/images/douyin_emoji/1f61b.png',
  '[礼物]': 'asset://assets/images/douyin_emoji/1f381.png',
  '[蛋糕]': 'asset://assets/images/douyin_emoji/1f382.png',
  '[派对]': 'asset://assets/images/douyin_emoji/1f389.png',
  '[不看]': 'asset://assets/images/douyin_emoji/1f648.png',
  '[炸弹]': 'asset://assets/images/douyin_emoji/1f4a3.png',
  '[憨笑]': 'asset://assets/images/douyin_emoji/1f600.png',
  '[悠闲]': 'asset://assets/images/douyin_emoji/1f6ac.png',
  '[晕]': 'asset://assets/images/douyin_emoji/1f635.png',
  '[囧]': 'asset://assets/images/douyin_emoji/1f644.png',
  '[阴险]': 'asset://assets/images/douyin_emoji/1f60f.png',
  '[惊恐]': 'asset://assets/images/douyin_emoji/1f628.png',
  '[难过]': 'asset://assets/images/douyin_emoji/1f641.png',
  '[斜眼]': 'asset://assets/images/douyin_emoji/1f612.png',
  '[左哼哼]': 'asset://assets/images/douyin_emoji/1f624.png',
  '[右哼哼]': 'asset://assets/images/douyin_emoji/1f624-new.png',
  '[咒骂]': 'asset://assets/images/douyin_emoji/1f92c.png',
  '[咖啡]': 'asset://assets/images/douyin_emoji/2615.png',
  '[西瓜]': 'asset://assets/images/douyin_emoji/1f349.png',
  '[衰]': 'asset://assets/images/douyin_emoji/1f622.png',
  '[太阳]': 'asset://assets/images/douyin_emoji/1f31e.png',
  '[月亮]': 'asset://assets/images/douyin_emoji/1f31c.png',
  '[发]': 'asset://assets/images/douyin_emoji/1f005.png',
  '[猪头]': 'asset://assets/images/douyin_emoji/1f437.png',
  '[凋谢]': 'asset://assets/images/douyin_emoji/1f940.png',
  '[红包]': 'asset://assets/images/douyin_emoji/1f9e7.png',
  '[拳头]': 'asset://assets/images/douyin_emoji/270a.png',
  '[胜利]': 'asset://assets/images/douyin_emoji/270c.png',
  '[抱拳]': 'asset://assets/images/douyin_emoji/1f64f.png',
  '[闭嘴]': 'asset://assets/images/douyin_emoji/1f910.png',
  '[弱]': 'asset://assets/images/douyin_emoji/1f44e.png',
  '[左边]': 'asset://assets/images/douyin_emoji/1f448.png',
  '[右边]': 'asset://assets/images/douyin_emoji/1f449.png',
  '[送心]': 'asset://assets/images/douyin_emoji/1f970.png',
  '[耶]': 'asset://assets/images/douyin_emoji/270c-new.png',
  '[捂脸]': 'asset://assets/images/douyin_emoji/1f926.png',
  '[色]': 'asset://assets/images/douyin_emoji/1f60d.png',
  '[打脸]': 'asset://assets/images/douyin_emoji/1f915.png',
  '[大笑]': 'asset://assets/images/douyin_emoji/1f604.png',
  '[哈欠]': 'asset://assets/images/douyin_emoji/1f971.png',
  '[震惊]': 'asset://assets/images/douyin_emoji/1f92f.png',
  '[大金牙]': 'asset://assets/images/douyin_emoji/1f9b7.png',
  '[偷笑]': 'asset://assets/images/douyin_emoji/1f92d.png',
  '[石化]': 'asset://assets/images/douyin_emoji/1f630.png',
  '[思考]': 'asset://assets/images/douyin_emoji/1f914.png',
  '[可怜]': 'asset://assets/images/douyin_emoji/1f97a.png',
  '[嘘]': 'asset://assets/images/douyin_emoji/1f92b.png',
  '[撇嘴]': 'asset://assets/images/douyin_emoji/1f615.png',
  '[尴尬]': 'asset://assets/images/douyin_emoji/1f605.png',
  '[笑哭]': 'asset://assets/images/douyin_emoji/1f602.png',
  '[生病]': 'asset://assets/images/douyin_emoji/1f637.png',
  '[奸笑]': 'asset://assets/images/douyin_emoji/1f60f-new.png',
  '[得意]': 'asset://assets/images/douyin_emoji/1f60e.png',
  '[坏笑]': 'asset://assets/images/douyin_emoji/1f62c.png',
  '[抓狂]': 'asset://assets/images/douyin_emoji/1f62b.png',
  '[钱]': 'asset://assets/images/douyin_emoji/1f911.png',
  '[亲亲]': 'asset://assets/images/douyin_emoji/1f61a.png',
  '[恐惧]': 'asset://assets/images/douyin_emoji/1f631.png',
  '[愉快]': 'asset://assets/images/douyin_emoji/1f604-new.png',
  '[玫瑰]': 'asset://assets/images/douyin_emoji/1f339.png',
  '[快哭了]': 'asset://assets/images/douyin_emoji/1f625.png',
  '[翻白眼]': 'asset://assets/images/douyin_emoji/1f644-new.png',
  '[赞]': 'asset://assets/images/douyin_emoji/1f44d.png',
  '[鼓掌]': 'asset://assets/images/douyin_emoji/1f44f.png',
  '[感谢]': 'asset://assets/images/douyin_emoji/1f64f-new.png',
  '[嘴唇]': 'asset://assets/images/douyin_emoji/1f444.png',
  '[胡瓜]': 'asset://assets/images/douyin_emoji/1f952.png',
  '[流泪]': 'asset://assets/images/douyin_emoji/1f622-new.png',
  '[啤酒]': 'asset://assets/images/douyin_emoji/1f37a.png',
  '[我想静静]': 'asset://assets/images/douyin_emoji/1f611.png',
  '[委屈]': 'asset://assets/images/douyin_emoji/1f641-new.png',
  '[飞吻]': 'asset://assets/images/douyin_emoji/1f618.png',
  '[再见]': 'asset://assets/images/douyin_emoji/1f44b.png',
  '[听歌]': 'asset://assets/images/douyin_emoji/1f3a7.png',
  '[发怒]': 'asset://assets/images/douyin_emoji/1f621.png',
  '[绝望的凝视]': 'asset://assets/images/douyin_emoji/1f61e.png',
  '[看]': 'asset://assets/images/douyin_emoji/1f436.png',
  '[熊吉]': 'asset://assets/images/douyin_emoji/1f43b.png',
  '[骷髅]': 'asset://assets/images/douyin_emoji/1f480.png',
  '[黑脸]': 'asset://assets/images/douyin_emoji/1f31a.png',
  '[呲牙]': 'asset://assets/images/douyin_emoji/1f601.png',
  '[吐]': 'asset://assets/images/douyin_emoji/1f92e.png',
  '[流汗]': 'asset://assets/images/douyin_emoji/1f613.png',
  '[摸头]': 'asset://assets/images/douyin_emoji/1f60c.png',
  '[红脸]': 'asset://assets/images/douyin_emoji/1f633.png',
  '[尬笑]': 'asset://assets/images/douyin_emoji/1f605-new.png',
  '[做鬼脸]': 'asset://assets/images/douyin_emoji/1f61c.png',
  '[睡]': 'asset://assets/images/douyin_emoji/1f62a.png',
  '[惊喜]': 'asset://assets/images/douyin_emoji/1f929.png',
  '[敲打]': 'asset://assets/images/douyin_emoji/1f915-new.png',
  '[吐彩虹]': 'asset://assets/images/douyin_emoji/1f308.png',
  '[大哭]': 'asset://assets/images/douyin_emoji/1f62d.png',
  '[比心]': 'asset://assets/images/douyin_emoji/1f91e.png',
  '[强壮]': 'asset://assets/images/douyin_emoji/1f4aa.png',
  '[碰拳]': 'asset://assets/images/douyin_emoji/1f91b.png',
  '[OK]': 'asset://assets/images/douyin_emoji/1f44c.png',
};

/// 运行时从抖音官方接口拉取的最新映射（优先于内置静态表）。
/// 注意：接口返回的是带签名/有效期的 douyinpic CDN URL，刷新即可续期。
Map<String, String> _dynamicDouyinEmoji = const {};

/// 解析单个表情 token：动态映射、移动端目录、网页词库依次兜底。
String? resolveDouyinEmoji(String token) =>
    _dynamicDouyinEmoji[token] ??
    douyinMobileEmojiAssets[token] ??
    douyinEmojiAssets[token];

/// 抖音 web 表情列表接口（同前端页面请求，参数集一致）。
const String douyinEmojiListBaseUrl =
    'https://live.douyin.com/aweme/v1/web/emoji/list'
    '?aid=6383&app_name=douyin_web&live_id=1&device_platform=web'
    '&language=zh-CN&enter_from=link_share&cookie_enabled=true'
    '&screen_width=1920&screen_height=1080&browser_language=zh-CN'
    '&browser_platform=Win32&browser_name=Edge&browser_version=151.0.0.0'
    '&os_name=Windows&os_version=10';

/// 拉取抖音最新表情映射并合并到现有动态表。
///
/// 策略：先匿名请求；失败且 [cookie] 非空（用户配置的登录态）时
/// 再带 cookie 重试一次。匿名成功则不暴露用户 cookie。
/// 接口需要 a_bogus 签名（复用 [DouyinSign.getAbogusUrl]）。
/// 全部失败（断网/签名变更/接口调整）静默保留现有映射，不抛异常。
/// [fetcher] 仅供测试注入（跳过网络与签名）。
Future<bool> refreshDouyinEmoji({
  String? cookie,
  Future<String> Function()? fetcher,
}) async {
  final effectiveCookie = (cookie == null || cookie.isEmpty) ? null : cookie;
  String text;
  if (fetcher != null) {
    try {
      text = await fetcher();
    } catch (_) {
      return false;
    }
  } else {
    // 匿名优先，失败再带 cookie。
    try {
      text = await _fetchDouyinEmojiList(null);
    } catch (e) {
      CoreLog.d('抖音表情匿名刷新失败: $e');
      if (effectiveCookie == null) {
        return false;
      }
      try {
        text = await _fetchDouyinEmojiList(effectiveCookie);
      } catch (e2) {
        CoreLog.d('抖音表情 cookie 刷新失败: $e2');
        return false;
      }
    }
  }
  try {
    final decoded = jsonDecode(text);
    final list = (decoded as Map<String, dynamic>)['emoji_list'];
    if (list is! List) return false;
    final map = <String, String>{};
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final name = item['display_name'];
      final urlList =
          (item['emoji_url'] as Map<String, dynamic>?)?['url_list'];
      if (name is String && urlList is List && urlList.isNotEmpty) {
        final url = _normalizeDouyinEmojiUrl(urlList.first.toString());
        if (url != null) {
          map[name] = url;
        }
      }
    }
    if (map.isEmpty) return false;
    _dynamicDouyinEmoji = {..._dynamicDouyinEmoji, ...map};
    CoreLog.d('抖音表情映射已刷新：${map.length} 项');
    return true;
  } catch (e) {
    CoreLog.d('抖音表情映射解析失败: $e');
    return false;
  }
}

String? _normalizeDouyinEmojiUrl(String value) {
  var url = value.trim();
  if (url.startsWith('//')) {
    url = 'https:$url';
  } else if (url.startsWith('http://')) {
    url = 'https://${url.substring('http://'.length)}';
  }
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    return null;
  }
  return uri.toString();
}

/// 请求抖音 emoji 列表（真实网络路径，计算 a_bogus 签名）。
/// [cookie] 为 null 表示匿名请求。
Future<String> _fetchDouyinEmojiList(String? cookie) async {
  final requestUrl = DouyinSign.getAbogusUrl(
    douyinEmojiListBaseUrl,
    DouyinSite.kDefaultUserAgent,
  );
  final headers = <String, dynamic>{
    'Authority': 'live.douyin.com',
    'Referer': 'https://live.douyin.com',
    'User-Agent': DouyinSite.kDefaultUserAgent,
  };
  if (cookie != null && cookie.isNotEmpty) {
    headers['cookie'] = cookie;
  }
  return HttpClient.instance.getText(requestUrl, header: headers);
}
