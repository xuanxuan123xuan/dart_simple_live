// 抖音直播分区封面图静态映射。
//
// 抖音 web 端不提供分区图片（首页 categoryData 的 partition 只有
// id/type/title，分类页与分区接口也都没有分区图）。这里借用
// B站直播分区封面（来源：B站 Area/getList 接口，i0.hdslb.com CDN），
// 按语义对应抖音 8 个一级分区：
//   101 聊天 → B站聊天室 / 102 音乐 → B站电台 / 103 游戏 → B站网游
//   104 二次元 → B站虚拟主播 / 105 舞蹈 → B站舞见 / 106 文化 → B站知识
//   107 生活 → B站生活 / 108 运动 → B站赛事
library;

/// key 为抖音分区 id_str（如 "101"、"103"）。
const Map<String, String> douyinPartitionImages = {
  '101': 'https://i0.hdslb.com/bfs/live/fe112b439e34d4ef3e254c00a9c0d3bd998043bd.png', // 聊天
  '102': 'https://i0.hdslb.com/bfs/live/a7adae1f7571a97f51d60f685823acc610d00a7e.png', // 音乐
  '103': 'https://i0.hdslb.com/bfs/live/3aa12550186a2f8c4dd9352f6c3fcc82054e594d.png', // 游戏
  '104': 'https://i0.hdslb.com/bfs/live/cdf8c5a456de00c456bc6dede3c19569ef2c40bf.png', // 二次元
  '105': 'https://i0.hdslb.com/bfs/vc/5837fa9608fab6c1465ec29c5abecab44f7bc376.png', // 舞蹈
  '106': 'https://i0.hdslb.com/bfs/live/c8e6d780a3182c37a96e79f4ed26fcb576f2520a.png', // 文化
  '107': 'https://i0.hdslb.com/bfs/live/fd7a23073b7ff9c7260c2fa8bf50e3738ecdc60a.png', // 生活
  '108': 'https://i0.hdslb.com/bfs/live/828cdd0bdce7dd20d599f1b19521139f1dc05300.png', // 运动
};

/// 判断字符串是否为可加载的 http(s) 图片地址。
///
/// 分区数据里常有无意义字符串（如分区 id 的 "101"），
/// 不能当作图片 URL 使用，需先经过该校验。
bool isHttpImageUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  final uri = Uri.tryParse(trimmed);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}
