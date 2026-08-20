// Generated from Kuaishou live emoji panel API
// (https://live.kuaishou.com/live_api/emoji/panel) on 2026-08-03.
// Source CDN: yximgs.com. Network URLs, not bundled assets.
//
// 内置表为抓取时的快照（兜底）；运行时可通过
// [refreshKuaishouEmoji] 拉取最新映射并覆盖，快手新增表情无需发版。
library;

import 'dart:convert';

import 'package:simple_live_core/src/common/core_log.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/danmaku/kuaishou_mobile_emoji_assets.dart';

const Map<String, String> kuaishouEmojiAssets = {
  '[666]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704763447505third_party_s1296657489.png',
  '[奸笑]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704776059816third_party_s1296748052.png',
  '[捂脸]':
      'https://bd.a.yximgs.com/bs2/emotion/1704776021202third_party_s1296747457.png',
  '[龇牙]':
      'https://bd.a.yximgs.com/bs2/emotion/1704775978144third_party_s1296746882.png',
  '[哼]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704775935917third_party_s1296746407.png',
  '[哦]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704775888472third_party_s1296745888.png',
  '[微笑]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704775840073third_party_s1296745254.png',
  '[老铁]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704766004548third_party_s1296668542.png',
  '[双鸡]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704765943430third_party_s1296668337.png',
  '[调皮]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704775798640third_party_s1296744691.png',
  '[呆住]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704775755675third_party_s1296744198.png',
  '[星星眼]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704775705283third_party_s1296743591.png',
  '[爱心]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704765876094third_party_s1296667852.png',
  '[疑问]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704775660342third_party_s1296742992.png',
  '[生气]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704775610489third_party_s1296742417.png',
  '[难过]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704775560543third_party_s1296741805.png',
  '[撇嘴]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704775517486third_party_s1296741380.png',
  '[惊讶]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704775445666third_party_s1296740420.png',
  '[羞涩]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704772289790third_party_s1296705324.png',
  '[色]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704772231770third_party_s1296704846.png',
  '[汗]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704772177310third_party_s1296704283.png',
  '[呕吐]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704772118979third_party_s1296703810.png',
  '[老司机]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704772048844third_party_s1296703216.png',
  '[头盔]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704771654524third_party_s1296700611.png',
  '[酷]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704771603139third_party_s1296700263.png',
  '[笑哭]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704771554781third_party_s1296699971.png',
  '[愉快]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704771498312third_party_s1296699382.png',
  '[委屈]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704771450694third_party_s1296699070.png',
  '[鄙视]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704771395457third_party_s1296698891.png',
  '[白眼]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704771346135third_party_s1296698660.png',
  '[安排]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704771294552third_party_s1296698182.png',
  '[点点关注]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704771236940third_party_s1296697797.png',
  '[鼓掌]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704771184363third_party_s1296697359.png',
  '[抱抱]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704766474596third_party_s1296670536.png',
  '[哈欠]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704771131055third_party_s1296696977.png',
  '[骂你]':
      'https://bd.a.yximgs.com/bs2/emotion/1704771079728third_party_s1296696446.png',
  '[大哭]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704771028940third_party_s1296696033.png',
  '[闭嘴]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704770709451third_party_s1296694128.png',
  '[惊恐]':
      'https://bd.a.yximgs.com/bs2/emotion/1704770650664third_party_s1296693781.png',
  '[红脸蛋]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704770591150third_party_s1296693499.png',
  '[亲亲]':
      'https://bd.a.yximgs.com/bs2/emotion/1704770453439third_party_s1296692624.png',
  '[冷汗]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704770395028third_party_s1296692231.png',
  '[晕]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704770038072third_party_s1296690336.png',
  '[皇冠]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704765811100third_party_s1296667470.png',
  '[火]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704763504359third_party_s1296657659.png',
  '[坏笑]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704769906157third_party_s1296689515.png',
  '[爆炸]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704763342710third_party_s1296657261.png',
  '[大便]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704763289677third_party_s1296657112.png',
  '[可怜]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704769849712third_party_s1296689281.png',
  '[抠鼻]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704769802638third_party_s1296689012.png',
  '[再见]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704769742626third_party_s1296688705.png',
  '[摄像机]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704763241589third_party_s1296656998.png',
  '[赞]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704762153449third_party_s1296652881.png',
  '[平底锅]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704769687542third_party_s1296688270.png',
  '[囧]':
      'https://bd.a.yximgs.com/bs2/emotion/1704769626325third_party_s1296687863.png',
  '[大哥]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704769568039third_party_s1296687559.png',
  '[玫瑰]':
      'https://bd.a.yximgs.com/bs2/emotion/1704763142635third_party_s1296656612.png',
  '[抓狂]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704769507289third_party_s1296687303.png',
  '[嘘]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704769442407third_party_s1296686829.png',
  '[快哭了]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704769347108third_party_s1296686284.png',
  '[骷髅]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704768884061third_party_s1296683458.png',
  '[偷笑]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704768706672third_party_s1296682428.png',
  '[落泪]':
      'https://bd.a.yximgs.com/bs2/emotion/1704768657909third_party_s1296681906.png',
  '[挑逗]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704768600457third_party_s1296681529.png',
  '[困]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704768550467third_party_s1296681259.png',
  '[睡觉]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704768494268third_party_s1296681034.png',
  '[右哼哼]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704768448493third_party_s1296680688.png',
  '[左哼哼]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704768392482third_party_s1296680332.png',
  '[打招呼]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704762100195third_party_s1296652661.png',
  '[流鼻血]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704768330183third_party_s1296680037.png',
  '[偷瞄]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704768270249third_party_s1296679827.png',
  '[吃瓜]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704768220721third_party_s1296679581.png',
  '[黑脸问]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704768168791third_party_s1296679234.png',
  '[旋转]':
      'https://bd.a.yximgs.com/bs2/emotion/1704768117560third_party_s1296678783.png',
  '[憨笑]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704768054223third_party_s1296678500.png',
  '[吐彩虹]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704767994674third_party_s1296678327.png',
  '[擦鼻涕]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704767940928third_party_s1296677841.png',
  '[怒言]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704767890021third_party_s1296677678.png',
  '[拜托]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704767838535third_party_s1296677360.png',
  '[加油]':
      'https://bd.a.yximgs.com/bs2/emotion/1704767780611third_party_s1296677057.png',
  '[暴汗]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704767728861third_party_s1296676729.png',
  '[想吃]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704767667849third_party_s1296676449.png',
  '[打脸]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704767617056third_party_s1296676208.png',
  '[吐血]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704767567911third_party_s1296675878.png',
  '[尴尬]':
      'https://bd.a.yximgs.com/bs2/emotion/1704767506569third_party_s1296675528.png',
  '[出魂儿]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704767441130third_party_s1296675286.png',
  '[大鼻孔]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704767388991third_party_s1296674947.png',
  '[嘣]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704767331411third_party_s1296674616.png',
  '[天啊]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704767271335third_party_s1296674239.png',
  '[石化]':
      'https://bd.a.yximgs.com/bs2/emotion/1704767221776third_party_s1296674013.png',
  '[皱眉]':
      'https://bd.a.yximgs.com/bs2/emotion/1704767005855third_party_s1296672942.png',
  '[装傻]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704766945094third_party_s1296672714.png',
  '[酸了]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704761625171third_party_s1296650672.png',
  '[柴犬]':
      'https://bd.a.yximgs.com/bs2/emotion/1704761562366third_party_s1296650505.png',
  '[狗粮]':
      'https://bd.a.yximgs.com/bs2/emotion/1704762211958third_party_s1296653006.png',
  '[期待]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704766537316third_party_s1296670779.png',
  '[红包]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704762630876third_party_s1296654958.png',
  '[干杯]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704762976549third_party_s1296656073.png',
  '[祈祷]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704762918273third_party_s1296655765.png',
  '[花谢了]':
      'https://bd.a.yximgs.com/bs2/emotion/1704763094568third_party_s1296656398.png',
  '[跪下]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704762867899third_party_s1296655667.png',
  '[南]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704762761234third_party_s1296655362.png',
  '[发]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704762689267third_party_s1296655142.png',
  '[板砖]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704763039720third_party_s1296656165.png',
  '[灯笼]':
      'https://bd.a.yximgs.com/bs2/emotion/1704762583000third_party_s1296654733.png',
  '[福字]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704762521906third_party_s1296654390.png',
  '[鞭炮]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704762474616third_party_s1296654064.png',
  '[烟花]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704762425707third_party_s1296653845.png',
  '[元宝]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704762370541third_party_s1296653559.png',
  '[钱]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704762316380third_party_s1296653319.png',
  '[气球]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704762265510third_party_s1296653172.png',
  '[庆祝]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704770972968third_party_s1296695686.png',
  '[礼花]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704766060554third_party_s1296668711.png',
  '[爱你]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704766815314third_party_s1296671857.png',
  '[摸头]':
      'https://bd.a.yximgs.com/bs2/emotion/1704766657395third_party_s1296671198.png',
  '[雾霾]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704766594591third_party_s1296670988.png',
  '[化妆]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704766889905third_party_s1296672534.png',
  '[涂指甲]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704761682759third_party_s1296650876.png',
  '[欢迎]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704762048343third_party_s1296652504.png',
  '[左拳]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704761978093third_party_s1296652142.png',
  '[右拳]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704761920283third_party_s1296651882.png',
  '[我爱你]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704761864978third_party_s1296651546.png',
  '[比心]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704761810228third_party_s1296651375.png',
  '[肌肉]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704761751472third_party_s1296651098.png',
  '[狮子]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704761502720third_party_s1296650143.png',
  '[龙]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704761427407third_party_s1296649954.png',
  '[狗]':
      'https://bd.a.yximgs.com/bs2/emotion/1704761371094third_party_s1296649726.png',
  '[网红猫]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704761307262third_party_s1296649487.png',
  '[猫]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704761245827third_party_s1296649373.png',
  '[老鼠]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704761189331third_party_s1296649156.png',
  '[不看]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704761136865third_party_s1296649061.png',
  '[不听]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704761074831third_party_s1296648807.png',
  '[不说]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704761014678third_party_s1296648623.png',
  '[猪头]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704760952536third_party_s1296648309.png',
  '[猪鼻子]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704760884297third_party_s1296648188.png',
  '[猪蹄]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704760771304third_party_s1296648058.png',
  '[羊驼]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704760711037third_party_s1296647965.png',
  '[麦克风]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704760647218third_party_s1296647852.png',
  '[跳舞]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704760582888third_party_s1296647756.png',
  '[蛋糕]':
      'https://bd.a.yximgs.com/bs2/emotion/1704760405763third_party_s1296647250.png',
  '[口红]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704760472494third_party_s1296647403.png',
  '[水枪]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704760254873third_party_s1296646780.png',
  '[空投]':
      'https://bd.a.yximgs.com/bs2/emotion/1704760193986third_party_s1296646575.png',
  '[手柄]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704760091452third_party_s1296646374.png',
  '[坑]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704759985787third_party_s1296646211.png',
  '[八倍镜]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704759889785third_party_s1296646065.png',
  '[网红]':
      'https://bd.a.yximgs.com/bs2/emotion/1704759766583third_party_s1296645553.png',
  '[优秀]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704759660137third_party_s1296645301.png',
  '[减1]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704720665766third_party_s1296409266.png',
  '[必胜]':
      'https://bd.a.yximgs.com/bs2/emotion/1704759542034third_party_s1296644941.png',
  '[戴口罩]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704704107430third_party_s1295984389.png',
  '[勤洗手]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704703259238third_party_s1295977084.png',
  '[心心]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704772346276third_party_s1296705763.png',
  '[哭笑]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704702678707third_party_s1295972366.png',
  '[点赞]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704701773745third_party_s1295965382.png',
  '[菜刀]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704762819173third_party_s1296655522.png',
  '[扎心]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704763391921third_party_s1296657345.png',
  '[拍一拍]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704699252327third_party_s1295948859.png',
  '[稳]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704780742645third_party_s1296794020.png',
  '[收到]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704782800053third_party_s1296805478.png',
  '[加1]':
      'https://bd.a.yximgs.com/bs2/emotion/1704782930366third_party_s1296806744.png',
  '[叉号]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704782991766third_party_s1296807145.png',
  '[对号]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704783055649third_party_s1296807447.png',
  '[no]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704783096203third_party_s1296807744.png',
  '[yes]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704783149616third_party_s1296808385.png',
  '[湿巾]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704783721396third_party_s1296812504.png',
  '[吃饭]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704783768169third_party_s1296812801.png',
  '[莫吉托]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704783816852third_party_s1296812989.png',
  '[香草蛋糕]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704783879438third_party_s1296813277.png',
  '[健身]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704783968269third_party_s1296813760.png',
  '[思考]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704784017068third_party_s1296813974.png',
  '[疯狂工作]':
      'https://bd.a.yximgs.com/bs2/emotion/1704784063813third_party_s1296814234.png',
  '[充满干劲]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704785056742third_party_s1296820406.png',
  '[放轻松]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704785103740third_party_s1296820865.png',
  '[卷]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704786813813third_party_s1296831667.png',
  '[熬夜]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704786853592third_party_s1296831948.png',
  '[先睡了]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704786910336third_party_s1296832209.png',
  '[emo]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704786943774third_party_s1296832458.png',
  '[听音乐]':
      'https://bd.a.yximgs.com/bs2/emotion/1704786984951third_party_s1296832685.png',
  '[好运来]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704787279186third_party_s1296834761.png',
  '[元气满满]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704787606436third_party_s1296836908.png',
  '[学习]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704787673918third_party_s1296837372.png',
  '[打电话]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704787717756third_party_s1296837621.png',
  '[熬夜工作]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704787761789third_party_s1296837795.png',
  '[一起嗨皮]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704787815614third_party_s1296838146.png',
  '[难受]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704787901952third_party_s1296838607.png',
  '[上吊]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704787935223third_party_s1296838745.png',
  '[吓]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704787981957third_party_s1296839028.png',
  '[发呆]':
      'https://bd.a.yximgs.com/bs2/emotion/1704788025440third_party_s1296839215.png',
  '[疲惫]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704788904736third_party_s1296845175.png',
  '[裂开]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704788951325third_party_s1296845410.png',
  '[强颜欢笑]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704788997306third_party_s1296845817.png',
  '[翻白眼]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704789037112third_party_s1296846026.png',
  '[难过至极]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704789078980third_party_s1296846236.png',
  '[美滋滋]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704789133176third_party_s1296846710.png',
  '[马上安排]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704789177867third_party_s1296847087.png',
  '[摸鱼]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704789217352third_party_s1296847412.png',
  '[敬礼]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704789256009third_party_s1296847689.png',
  '[求求了]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704789289580third_party_s1296847957.png',
  '[赢麻了]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704789337176third_party_s1296848206.png',
  '[遥遥领先]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704789382578third_party_s1296848447.png',
  '[辣眼睛]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704789443283third_party_s1296848822.png',
  '[ok]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704789999083third_party_s1296852648.png',
  '[握手]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704790046552third_party_s1296852850.png',
  '[抱拳]':
      'https://bd.a.yximgs.com/bs2/emotion/1704790113221third_party_s1296853443.png',
  '[早上好]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704790167344third_party_s1296853922.png',
  '[胡思乱想]':
      'https://ali2.a.yximgs.com/bs2/emotion/1704790657229third_party_s1296858542.png',
};

/// 运行时从快手接口拉取的最新映射（优先于内置静态表）。
Map<String, String> _dynamicKuaishouEmoji = const {};

const Map<String, String> _kuaishouEmojiAliasMap = {
  '[點讚]': '[点赞]',
  '[讚]': '[赞]',
  '[點點關注]': '[点点关注]',
  '[早安]': '[早上好]',
  '[哈囉]': '[打招呼]',
  '[愛你]': '[爱你]',
  '[我愛你]': '[我爱你]',
  '[發]': '[发]',
  '[發財]': '[发财]',
  '[打電話]': '[打电话]',
  '[聽音樂]': '[听音乐]',
  '[學習]': '[学习]',
  '[放輕鬆]': '[放轻松]',
  '[睡覺]': '[睡觉]',
  '[iloveu]': '[ILoveU]',
};

/// 解析单个表情 token：运行时映射、移动端词库、网页词库依次兜底。
String? resolveKuaishouEmoji(String token) => _resolveKuaishouEmojiToken(token);

String? _resolveKuaishouEmojiToken(String token) {
  final candidates = <String>[token];
  final lower = token.toLowerCase();
  if (lower != token) {
    candidates.add(lower);
  }
  for (var index = 0; index < candidates.length; index += 1) {
    final alias = _kuaishouEmojiAliasMap[candidates[index]];
    if (alias != null && !candidates.contains(alias)) {
      candidates.add(alias);
    }
  }
  for (final candidate in candidates) {
    if (candidate.isEmpty) continue;
    final resolved = _dynamicKuaishouEmoji[candidate] ??
        kuaishouMobileEmojiAssets[candidate] ??
        kuaishouEmojiAssets[candidate];
    if (resolved != null) {
      return resolved;
    }
  }
  return null;
}

const String kuaishouEmojiPanelUrl =
    'https://live.kuaishou.com/live_api/emoji/panel';

/// 拉取快手最新表情映射并覆盖静态表。
///
/// 仅使用匿名公开接口；失败时保留内置映射，不读取账号 Cookie。
/// 全部失败（断网/接口变更）静默保留现有映射，不抛异常。
/// [fetcher] 仅供测试注入（跳过网络）。
Future<void> refreshKuaishouEmoji({
  String? cookie,
  Future<String> Function()? fetcher,
}) async {
  String text;
  if (fetcher != null) {
    try {
      text = await fetcher();
    } catch (_) {
      return;
    }
  } else {
    try {
      text = await HttpClient.instance.getText(kuaishouEmojiPanelUrl);
    } catch (e) {
      CoreLog.d('快手表情匿名刷新失败: $e');
      return;
    }
  }
  try {
    final decoded = jsonDecode(text);
    final data = (decoded as Map<String, dynamic>)['data'];
    if (data is! Map) return;
    final map = <String, String>{};
    data.forEach((key, value) {
      if (key is String && value is String) {
        final url = _normalizeKuaishouEmojiUrl(value);
        if (url != null) {
          map[key] = url;
        }
      }
    });
    if (map.isEmpty) return;
    _dynamicKuaishouEmoji = {
      ..._dynamicKuaishouEmoji,
      ...map,
    };
    CoreLog.d('快手表情映射已刷新：${map.length} 项');
  } catch (e) {
    CoreLog.d('快手表情映射解析失败: $e');
  }
}

String? _normalizeKuaishouEmojiUrl(String value) {
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
