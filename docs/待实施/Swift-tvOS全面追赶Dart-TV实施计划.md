# Swift tvOS 全界面对齐 Dart TV 实施计划

当前进度 **2 / 20** 项验收完成。

以 `simple_live_tv_app` 的 18 个注册页面及其操作面板为基线，对照 `simple_live_tvos_native`。目标为 Apple TV 上的功能和操作对齐，保留 SwiftUI、AVPlayer、KSPlayer 和 tvOS 17 最低版本。

| 编号 | 界面 | Dart TV 对照与交付条件 | 状态 |
| --- | --- | --- | --- |
| TV-01 | 使用须知 | 首次使用、持久化同意版本、拒绝后保留须知、重新启动 | 完成 |
| TV-02 | 首页 | 关注预览、管理、刷新、同步、多屏入口；进房返回恢复焦点 | 待验收 |
| TV-03 | 热门直播 | 平台切换、加载失败及分页重试，处理末页和过期请求 | 待验收 |
| TV-04 | 类目和详情 | 递归类目、逐层浏览、「全部」、分页、焦点和返回 | 待验收 |
| TV-05 | 房间及主播搜索 | 分模式、平台切换、分页及错误状态、从结果进房 | 阻塞 |
| TV-06 | 链接与小红书发现 | 公用链接解析、分享链接平台识别、原生小红书目录及游标、不可用提示 | 阻塞 |
| TV-07 | 收藏／关注 | 旧数据迁移、取消数量截断、特别关注、开播三态、刷新全部/本页、进页和定时刷新、筛选、样式和分页 | 待验收 |
| TV-08 | 观看历史 | 保留观看时间、去重、单条删除、清空确认、来源列表换台及导入 | 待验收 |
| TV-09 | 单房间控制 | 状态、暂停/继续、音量、刷新、换台、收藏列表和房内设置，保留清晰度与线路选择 | 待验收 |
| TV-10 | 恢复与定时关闭 | 区分确实下播与网络失败，线路回退、自动降档、定时停止、暂停及前后台保留意图 | 待验收 |
| TV-11 | 频道与轮播 | 各来源换台队列、轮播管理、关播/失败分别设置、顺序或随机并保证有限退出 | 待验收 |
| TV-12 | 弹幕 | 尺寸、速度、透明度、描边、区域/行数、表情、重点动态、去重和屏蔽词 | 进行中 |
| TV-13 | 多屏选房 | 首页、关注、播放入口，支持历史、搜索和链接，去重及限制 2–4 路 | 待验收 |
| TV-14 | 多屏观看 | 均分、主次、单格放大、房间增删、转单路、每路和整组控制、音频隔离及资源释放 | 待验收 |
| TV-15 | 设置 | 播放、弹幕、关注、多屏、账号、关于六区，完成持久化及实际接线，原生播放器选项替代 mpv 专用项 | 待验收 |
| TV-16 | 账号和扫码 | B 站、斗鱼扫码；斗鱼、抖音、快手、小红书 Cookie 管理；快手主备用；Keychain | 待验收 |
| TV-17 | 远程同步 | 现有 WebSocket 协议、房间码、二维码、倒计时、站点与代理、Dart 发送端互通 | 待验收 |
| TV-18 | 局域网同步 | UDP 发现、IP/二维码、现有 HTTP 路由及配置包，合并、覆盖、分块、回执和导入结果 | 待验收 |
| TV-19 | WebDAV | 凭据管理、连接验证、上传/恢复、进度、类别开关、兼容 Dart 新旧备份 | 待验收 |
| TV-20 | 关于和更新 | 本机版本、构建号、查询稳定 `tvos-native-v<版本>` Release，发布页二维码和错误状态 | 完成 |

## 实施与验收顺序

1. 导航、发现及个人列表先落地。统一平台能力、房间标识、类目、状态和链接解析。
2. 单房间、弹幕和播放设置落地后，复用播放会话实现多屏。每路独立持有播放、声音和弹幕状态。
3. 完成账号后接入远程、局域网、WebDAV 与关于。三种导入使用同一校验与存储逻辑，保留未勾选数据。覆盖需确认，分块完整后提交。
4. 各项目验证正常入口、失败状态和遥控焦点。分别记录离线测试、模拟器、真实平台及 Apple TV 真机验收。重点验证旧数据迁移、异步取消、暂停意图、四路隔离和 Dart 发送端互通。

## 进度维护

- **每完成一项，立即更新本文件**，修改该项状态和顶部完成数，追加日期、交付内容、验证命令及结果。
- 状态使用 `待实施`、`进行中`、`待验收`、`阻塞`、`完成`。必要验收完成后才计入完成项。阻塞项记录具体依赖和剩余验收。
- 每完成一个可独立验证的小改动，本地提交一次。项目完成时将对应进度更新与实现放进同一提交，提交消息带 `TV-xx`。已有未提交改动保持独立，推送按后续指令执行。

## 进度记录

| 日期 | 项目 | 状态 | 交付与验证 |
| --- | --- | --- | --- |
| 2026-11-18 | TV-01 | 待验收 | 新增版本化使用须知；同意前不启动首页或恢复账号，拒绝后停留。`swiftc -parse`、`git diff --check` 通过；待在 Apple TV 模拟器验证首次启动、拒绝、同意及重启。 |
| 2026-11-18 | TV-03 | 待验收 | 首页推荐和搜索各自持有分页状态；首屏/分页分别重试，显示末页，过滤重复房间和过期结果。分页与乱序返回离线断言通过；首页通过 tvOS 17 SDK 类型检查（播放器和平台服务用替身）；待用遥控器和真实平台验证。 |
| 2026-11-18 | TV-04 | 待验收 | 五个平台恢复目录分组，抖音保留递归子类目，快手逐页获取目录。独立目录/列表路由支持逐层返回、记忆焦点、重试和「全部」。离线三层目录用例和 tvOS 目标源码类型检查通过（播放器用替身）；待验证遥控焦点及平台数据。 |
| 2026-11-18 | TV-05 | 待验收 | 增加「直播间／主播」模式。B 站、虎牙、斗鱼和快手使用平台主播搜索，抖音按 Dart 方案从直播结果生成主播列表；保留开播状态和进房入口。tvOS 目标源码及解析测试类型检查通过；待联机验证五个平台。 |
| 2026-11-18 | TV-01 | 完成 | tvOS 26.5 Apple TV 4K 模拟器遥控测试通过：首启默认焦点、拒绝后仍停留、同意进入首页、终止后重启不重复提示。临时 UI 测试构建仅替换播放器；完整工程另通过 `build-for-testing`。 |
| 2026-11-18 | TV-06 | 阻塞 | 公用房间号/分享链接入口已接线，支持六个平台、短链和安全的重定向边界，小红书发现不可用时保留链接入口。完整 tvOS 模拟器离线测试 18 项通过（含分页、类目、主播与链接）；真实短链和进房待验收。Dart 小红书发现依赖 Android WebView 会话，tvOS SDK 无 WebKit；缺少可用的 tvOS 发现服务传输，原生目录和游标尚未实现。 |
| 2026-11-18 | TV-07 / TV-08 | 进行中 | 迁移旧关注和历史记录，取消数量截断；持久化特别关注和新记录的观看时间，旧记录保留原顺序及未知时间。提供按房间合并、删除和覆盖的历史存储接口；Apple TV 模拟器 `LibraryStoreTests` 通过。 |
| 2026-11-18 | TV-07 | 待验收 | 关注页增加特别关注、平台和开播筛选、手动及定时刷新、三种布局、分页和对应设置。按平台串行查询，失败保留「状态未知」；模拟器 `FavoriteStatusStoreTests` 和 `LibraryStoreTests` 通过。待真实账号及遥控焦点验收。 |
| 2026-11-18 | TV-08 / TV-11 | 进行中 | 历史页显示观看时间、支持单条删除和清空确认；从历史、关注、推荐、类目和搜索进房时带上来源队列，可手动换台。模拟器 `LibraryStoreTests` 通过。历史导入尚待同步接线，轮播和真实播放换台尚待验证。 |
| 2026-11-18 | TV-02 | 进行中 | 独立首页和热门页，增加快捷入口及 6 条关注预览，提供管理、刷新与查看全部，记录进房前的房间焦点。`xcodebuild` tvOS 模拟器离线套件及 `git diff --check` 通过；待同步、多屏入口及遥控焦点验收。 |
| 2026-11-18 | TV-09、TV-10 | 待验收／进行中 | 单房间增加播放状态、暂停/继续、刷新、收藏列表、房内音量和静音；AVPlayer 与 KSPlayer 共享同一房间会话的暂停意图和音量，线路回退或退到后台不会重置。tvOS 模拟器离线套件及 `git diff --check` 通过；待实际直播和遥控验收，并补齐降档、下播分类和定时停止。 |
| 2026-11-18 | TV-10 | 进行中 | 定时关闭可选 15–120 分钟并显示倒计时；换台和前后台沿用原截止时间，时间到立即停止视频与弹幕。平台明确下播时才显示未开播。tvOS 离线套件和 `PlaybackRecoveryTests` 通过，待自动降档和实播验收。 |
| 2026-11-18 | TV-10 | 待验收 | 加入可关闭的自动降档：起播／恢复后预热，30 秒内出现两次独立缓冲时选择最近的已知较低档，且限制降档频率。未知档位继续用线路回退。`AutoQualityRecoveryTests` 和 tvOS 离线套件通过；待 Apple TV 实播验证断线、连续缓冲、定时及前后台。 |
| 2026-11-19 | TV-11 | 待验收 | 独立保存和管理轮播列表，可从关注或房内加入、移除及排序。关播和失败分别启用，选择关注或轮播列表，支持顺序和随机；实时确认新房间开播，每个候选最多尝试一次，稳定播放后重置。tvOS 离线套件通过，待真机交叉平台轮播验收。 |
| 2026-11-19 | TV-12 | 进行中 | 新增弹幕大小、速度、透明度、描边，以及按区域或按行数显示；设置即时接入播放器，保留旧版默认样式。`DanmakuOverlayTests` 验证轨道范围、重排、透明度和字号；tvOS 离线套件通过。 |
| 2026-11-19 | TV-12 | 进行中 | 新增文字屏蔽词的添加、删除和合并接口；弹幕支持按同一用户或所有用户过滤重复内容，可调整窗口和步长。`DanmakuFilterTests` 与 tvOS 离线套件通过；Dart 正则规则、表情与重点动态仍待实现。 |
| 2026-11-19 | TV-12 | 进行中 | 重点动态只汇总过滤后弹幕，支持统计跨度、起显次数、展示时长以及隐藏控制面板时是否显示，计数及可见条数有上限。`DanmakuHighlightsTests` 和 tvOS 离线套件通过。 |
| 2026-11-19 | TV-12 | 进行中 | 接入哔哩哔哩弹幕携带的图片表情和开关，限制下载域名、大小和并发，图片不可用时保留原文字。图片分段及域名限制测试、tvOS 离线套件通过；其余平台表情映射和 Dart 正则屏蔽规则仍缺。 |
| 2026-11-19 | TV-12 | 进行中 | 屏蔽词支持 Dart TV 的 `/…/` 写法，并以 Foundation 正则匹配原始弹幕。添加时提示语法错误，已存的无效规则会跳过。macOS 上用隔离的 `swift test` 运行 `DanmakuFilterTests` 和 `LibraryStoreTests`，共 7 项通过；相关源码和测试通过 `swiftc -typecheck`（tvOS 17 模拟器目标）。仍待其余平台表情映射和电视端验收。 |
| 2026-11-19 | TV-20 | 进行中 | 核对 Dart TV 的手动更新交互及原生版本配置 `0.2.0 (3)`。新增可分页查询 GitHub Release 的服务，筛选稳定的原生 tvOS 标签并按三段版本号排序。隔离运行 `swift test --disable-sandbox --filter TVOSReleaseServiceTests`，5 项通过，覆盖数值比较、跨页选择、其他产品和预发布过滤、无版本、无效响应和 HTTP 限流后重试。 |
| 2026-11-19 | TV-16 | 进行中 | 统一 B 站和斗鱼扫码后的校验、Keychain 会话恢复、退出与错误状态，斗鱼保存 safeAuth 下发的续签 Cookie。Apple TV 4K 模拟器 `xcodebuild test -only-testing:SimpleLiveTVOSTests/AccountSessionTests CODE_SIGN_IDENTITY=-` 5 项通过，`git diff --check` 通过；完整扫码、其他平台与账号页仍待验收。 |
| 2026-11-19 | TV-16 | 进行中 | 斗鱼、抖音、快手、小红书可校验和持久化 Cookie，快手分别保存主账号与备用账号，并在认证拒绝时逐次回退。抖音支持 ttwid，快手保留 Kww 和过期时间；离线配置状态与平台已确认登录分开显示。Apple TV 4K 模拟器 `xcodebuild test -only-testing:SimpleLiveTVOSTests/AccountSessionTests -only-testing:SimpleLiveTVOSTests/ProviderAccountTests CODE_SIGN_IDENTITY=-` 共 11 项通过，覆盖真实 Keychain 读写、旧条目、重新实例化恢复、退出、失败与主备回退。 |
| 2026-11-19 | TV-16 | 进行中 | 交付同步接口 `NativeCoreClient.prepareSyncAccounts(_:)`，供 `SyncImporter` 直接使用。先校验所选凭据，再以一次 Keychain 更新提交，保留未选槽位。旧版条目自动迁移，准备后检测到用户修改或退出时拒绝提交。Apple TV 4K 模拟器 `xcodebuild test -only-testing:SimpleLiveTVOSTests/AccountImportTests -only-testing:SimpleLiveTVOSTests/AccountSessionTests -only-testing:SimpleLiveTVOSTests/ProviderAccountTests -only-testing:SimpleLiveTVOSTests/SyncProfileTests CODE_SIGN_IDENTITY=-` 共 18 项通过。`git diff --check` 通过。 |
| 2026-11-19 | TV-16 | 待验收 | 交付独立 `AccountSettingsView()`，含扫码、遮蔽录入、快手主备和清除确认。Apple TV 4K 模拟器临时账号测试包 `xcodebuild test -only-testing:TV16UITests CODE_SIGN_IDENTITY=-` 1 项通过，验证遥控选中抖音、真实进程重启恢复测试凭据、确认清除及再次重启后保持未配置。启用 `SIMPLELIVE_LIVE_SMOKE=1` 运行 `xcodebuild test-without-building` 的两项 QR Challenge 测试，真实 B 站和斗鱼发码及未扫码轮询均通过。`git diff --check` 通过。仍需手机完成两站扫码确认，使用有效和过期的真实 Cookie 验证四个平台的认证请求及快手双账号回退，并在 Apple TV 真机验证输入与遥控。 |
| 2026-11-19 | TV-13 | 进行中 | 沿用选房草稿，修复预选房间的去重与上限，接入关注、历史、分页搜索及公共链接解析。切换来源时取消过期请求，支持搜索分页重试。Apple TV 模拟器 `xcodebuild -only-testing:SimpleLiveTVOSTests/MultiRoomSelectionTests test` 2 项通过，`git diff --check` 通过。待接入三个入口和多屏观看。 |
| 2026-11-19 | TV-12 | 进行中 | 斗鱼弹幕接入官方词库和通用 Twemoji，保留未知标签与原始文字顺序。共用图片渲染在下载失败时保留完整表情标签，关闭图片表情后以纯文字绘制。Apple TV 4K 模拟器 `xcodebuild test -only-testing:SimpleLiveTVOSTests/ProviderParsingTests -only-testing:SimpleLiveTVOSTests/DanmakuOverlayTests CODE_SIGN_IDENTITY=-` 共 18 项通过；`python3 tool/generate_tvos_danmaku_emoji.py --check` 和 `git diff --check` 通过。 |
| 2026-11-19 | TV-03 | 待验收 | 修复斗鱼热门首屏误报末页，改用有可信 `pgcnt` 的公开目录；校验目录回包格式，保留重试入口。离线：`xcodebuild test -skip-testing:SimpleLiveTVOSTests/ProviderSmokeTests` 的 36 项通过，其中分页测试覆盖同页重试、去重、末页和乱序平台切换。模拟器：Apple TV 4K（tvOS 26.5）遥控专项另行记录。真实平台：用 macOS 上编译的原生适配器探针验证 B 站、虎牙、斗鱼和抖音首两页；快手为单页。`curl` 验证斗鱼新接口样本共 42 页，末页返回 49 条。真机：`xcrun devicectl list devices` 无配对设备，待复验焦点、返回和真实断网重试。 |
| 2026-11-19 | TV-04 | 待验收 | 修复斗鱼类目目录对成功响应的识别，并校验父子类目数组。离线：`ProviderParsingTests.testDouyinCategoryTreePreservesThreeLevelsAndParentKeys` 通过。模拟器：三层目录、「全部」、重试及逐层返回的遥控专项另行记录。真实平台：macOS 原生适配器探针获得五个平台目录和所选类目的前两页。斗鱼修复后取到 10 个根类目，实例在第二页结束。真机：`xcrun devicectl list devices` 无配对设备，待复验长列表滚动、焦点及逐级返回。 |
| 2026-11-19 | TV-08、TV-17、TV-18、TV-19 | 进行中 | 用 Dart 生成新版配置包、旧历史文件和旧式配置样例。共用导入流程支持关注、观看时间、屏蔽词及账号凭据解析，选定类别可合并或经确认后覆盖，分块按发送顺序收齐才交付。隔离运行 `swift test --disable-sandbox --package-path /private/tmp/sl-sync-package`，8 项通过，覆盖未选类别、未确认覆盖、非法数据、账号提交失败、缺块及超时。待接同步入口、TV-16 接口及传输验收。 |
| 2026-11-19 | TV-12 | 进行中 | 虎牙弹幕接入官方默认和动漫等词库，按官方映射优先、Twemoji 兜底的顺序解析，未收录的标签保留文字。Apple TV 4K 模拟器 `xcodebuild test -only-testing:SimpleLiveTVOSTests/ProviderParsingTests CODE_SIGN_IDENTITY=-` 12 项通过，包含 Tars 消息与两个图片 CDN；`curl` 检查两处官方样图均为 HTTP 200 PNG，词库生成检查与 `git diff --check` 通过。 |
| 2026-11-19 | TV-12 | 进行中 | 快手弹幕接入移动端及网页内置词库，支持繁简别名和大小写别名。保留闭合的未知标签，按 Dart 的 UTF-16 长度规则清除短的未闭合尾片及残留替换字符，清理后为空的消息丢弃。Apple TV 4K 模拟器 `xcodebuild test -only-testing:SimpleLiveTVOSTests/ProviderParsingTests CODE_SIGN_IDENTITY=-` 14 项通过；`curl` 获取 WebP 和 PNG 样图均为 HTTP 200，词库生成检查与 `git diff --check` 通过。 |
| 2026-11-19 | TV-07 | 待验收 | 离线：完整工程 `xcodebuild test-without-building -skip-testing:SimpleLiveTVOSTests/ProviderSmokeTests` 36 项通过，其中迁移测试保留旧版 205 个去重房间及特别关注，刷新测试区分下播与故障并覆盖刷新时移除。模拟器：临时固定数据工程 `xcodebuild test -only-testing:RemoteAcceptance/RemoteAcceptanceTests/testTV07FavoriteStatesFiltersPagingAndReturn` 通过，遥控完成刷新全部／本页、翻页、筛选、进房和返回原卡片。真实平台：macOS 探针使用原生适配器查到 B 站、虎牙及快手开播／未开播样本；真实账号关注连续刷新未测，当前为游客会话。真机：无配对设备，待核验进页、定时刷新、布局切换和大列表遥控。 |
| 2026-11-19 | TV-02 / TV-13 | 进行中／待验收 | 首页、关注和房内均接入选房；房内预选当前房间，确认后进入多屏。Apple TV 模拟器 `build-for-testing` 及先前 2 项 `MultiRoomSelectionTests` 通过，待遥控焦点、入口返回和真实搜索／链接验收。首页同步仍由对应项目接线。 |
| 2026-11-19 | TV-14 / TV-15 | 待验收／进行中 | 单屏与多屏共用播放、恢复和弹幕会话；新增均分、主次、单格放大、房间增删、转单路及每路和整组控制。保留原生播放参数草稿并接入会话。Apple TV 模拟器 `xcodebuild test -only-testing:SimpleLiveTVOSTests/MultiRoomGroupTests -only-testing:SimpleLiveTVOSTests/PlaybackTuningTests` 6 项通过、网络媒体测试默认跳过，`git diff --check` 通过。待实播、遥控和设置首页接线。 |
| 2026-11-19 | TV-20 | 完成 | 独立 `AboutUpdateView()` 从应用 Bundle 显示版本与构建号，手动查询稳定发布，展示加载、无版本、失败重试、新旧版本与发布页二维码。设置首页入口由多屏与播放整合。完整原生工程 `xcodebuild build-for-testing` 通过，`xcodebuild test -only-testing:SimpleLiveTVOSTests/TVOSReleaseServiceTests` 5 项通过。Apple TV 4K（tvOS 26.5）临时设置页 `xcodebuild -scheme TV20QA test-without-building` 1 项通过，覆盖版本与构建号、加载、失败重试、较新／相同／较旧版本、无稳定版本以及遥控返回焦点。`xcrun simctl io <UDID> screenshot` 截取电视输出，jsQR 解码为样本版本的完整 GitHub 发布页。原生服务实连 GitHub Releases API，限流恢复后 HTTP 200 并确认当前暂无稳定 tvOS Release。`xcrun devicectl list devices` 未发现配对真机，扫码验收使用模拟器截图。`git diff --check` 通过。 |
| 2026-11-19 | TV-12 | 进行中 | 快手匿名刷新公开表情面板，刷新结果优先于移动端和网页内置词库，失败时继续使用内置表。复用无 Cookie、有超时和大小限制且拒绝重定向的下载器。Apple TV 4K（tvOS 26.5）`xcodebuild test -skip-testing:SimpleLiveTVOSTests/ProviderSmokeTests CODE_SIGN_IDENTITY=-` 离线 72 项通过，1 项多屏实播用例按条件跳过。临时 `TV12LiveProbe` 通过，实际下载并解码斗鱼、虎牙、快手与 Twemoji 样图，验证无效图片返回失败，以及匿名面板返回 207 项。词库生成检查与 `git diff --check` 通过。剩余交付为抖音富文本和内置词库表情。`xcrun devicectl list devices` 无配对设备，待 Apple TV 真机在 B 站、斗鱼、虎牙、快手直播间复验图文顺序、未知标签、快手尾片、图片失败回退及遥控开关重启后持久化，并复验样式切换、去重、普通／正则屏蔽和重点动态。 |
| 2026-11-19 | TV-03、TV-04 | 待验收 | 修复短网格中方向键绕过首屏重试、房卡及分页按钮的问题。临时固定数据工程运行 `xcodebuild test -only-testing:RemoteAcceptance`，TV-03、TV-04 两项通过。遥控覆盖热门切平台、首屏和分页重试、去重、末页及返回原卡片，类目覆盖三层浏览、「全部」、重试和逐级返回。完整工程的临时联网用例 `PlaybackAcceptanceTests.testDouyuRecommendedAndCategoryPagination` 在 tvOS 模拟器通过。Apple TV 真机验收仍缺配对设备。 |
| 2026-11-19 | TV-05 | 阻塞 | 沿用首屏重试、房卡及分页区的焦点修复。离线解析测试确认主播房号及开播状态。固定数据工程 `xcodebuild test -only-testing:RemoteAcceptance/RemoteAcceptanceTests/testTV05SearchModesPaginationRetryAndReturn` 通过，遥控验证切模式、切平台、首次和分页失败重试、末页、进房返回及保留关键词。macOS 原生适配器探针验证 B 站、虎牙、斗鱼的两种搜索及快手主播搜索。抖音两种搜索、快手房间搜索以游客访问时都要求登录或重新验证，快手房间接口返回 `result=10`。需要有搜索权限的会话复验这三个入口及分页，并在配对 Apple TV 真机上复验遥控。 |
| 2026-11-19 | TV-11 | 待验收 | 离线 `ChannelRotationTests` 和 `LibraryStoreTests` 通过，覆盖来源顺序、按平台去重、随机候选、有限退出及独立轮播列表持久化。临时固定数据工程执行 `xcodebuild test-without-building -only-testing:RemoteAcceptance`，三个轮播用例通过，包括 B 站下播后跳过已下播的斗鱼并进入虎牙、仅启用关播时播放失败不触发，以及失败随机轮播无可用候选时停留重试。五个平台真实房间分别在完整模拟器构建中起播。真实直播间之间自动轮播、轮播管理遥控和 Apple TV 真机验收仍待实测，当前无配对设备。 |
| 2026-11-19 | TV-08、TV-17、TV-18、TV-19 | 进行中 | 共用接收流程加上预览、确认、取消和限时回执，历史保留 Dart 微秒时间。配置包仅映射 tvOS 有对应控件的通用设置，账号通过 TV-16 的事务接口准备并提交。隔离 `swift test --package-path /private/tmp/sl-sync-package` 共 12 项通过，断言未确认覆盖时资料不变、不同类别保留和 Dart 新旧格式。 |
| 2026-11-19 | TV-14 | 待验收 | Apple TV 4K 模拟器 `xcodebuild -xctestrun MultiRoomSmoke.xctestrun -only-testing:SimpleLiveTVOSTests/MultiRoomGroupTests/testFourPlayersAdvanceAndDanmakuStreamsStaySeparate test-without-building` 通过。验证三路 AVPlayer HLS 与一路 KSPlayer FLV 同时推进、逐路暂停、静音切换、逐路模拟弹幕隔离以及退出后媒体后端和四条弹幕流释放。首次公网 FLV 样本未起播，同一样本下载后经本机 HTTP 服务复测通过。待遥控流程和 Apple TV 真机四路实播。 |
| 2026-11-19 | TV-15 | 进行中 | 播放新增画面比例、分档清晰度和恢复默认，解码与缓冲接入原生引擎；多屏新增持久化布局、间距、默认声音和弹幕。Apple TV 4K 模拟器 `xcodebuild build-for-testing` 与 `xcodebuild test-without-building` 通过，89 项中通过 78 项、按默认配置跳过 11 项，含实际 AVPlayer 缓冲参数和多屏默认值。待设置首页接线提交和遥控复验。 |
| 2026-11-19 | TV-17 | 进行中 | 接入 Dart 房间 WebSocket 握手、房间成员、600 秒有效期、心跳、国内与 Cloudflare 站点及 HTTP CONNECT 代理配置。用 `dart tool/probe_tvos_sync.dart remote <站点> <房间码>` 在两个现有站点分别通过 `roomJoined` 和两段 `ack`，Swift 接收端均持久化两条历史。独立 XCTest 通过协议帧和代理地址测试；待电视端二维码、倒计时、配置代理和账号实测。 |
| 2026-11-19 | TV-18 | 进行中 | 接入 UDP 23235 发现与 HTTP 23234，兼容新版配置包及 Dart 关注、历史、屏蔽词、标签和账号路由，完整校验与电视端覆盖确认后返回导入结果。用 `dart tool/probe_tvos_sync.dart lan http://127.0.0.1:23234` 通过 UDP 请求、`/info`、两段屏蔽词及配置包历史导入，Swift 校验持久化内容。独立 XCTest 通过收齐与确认后才写入的断言；待电视端广播、扫码及遥控验收。 |
| 2026-11-19 | TV-10 | 待验收 | 离线 `PlaybackFailoverTests`、`PlaybackRecoveryTests` 和 `AutoQualityRecoveryTests` 通过。完整 tvOS 模拟器运行临时 `PlaybackAcceptanceTests`，无效首线回退到真实 HLS 样例，音量、静音和暂停在同一引擎重开后保留；两次独立缓冲的状态注入触发会话降到最近较低档。遥控用例 `testTV10SleepDeadlineAndBackgroundPause` 通过，Home 退后台并回前台后仍暂停，15 秒测试倒计时到点后关闭设置、显示停止状态并将焦点移到返回；第一次即时焦点断言失败，等待弹层动画结束后的复验通过。真实 HLS／FLV 样例单独复跑通过。多屏与播放对话已收到复现和复验结果。Apple TV 未配对，真实直播的连续缓冲、实际分钟定时和设备前后台仍待验收。 |
| 2026-11-19 | TV-07 | 待验收 | 补跑固定数据工程 `xcodebuild test -only-testing:RemoteAcceptance` 的关注进页、定时及三种布局专项，三项通过。模拟器验证进页后重查未知状态，1 分钟测试间隔到期后更新开播三态，按持久化的默认、紧凑和大卡片偏好启动时列宽对应变化且房卡保留。真实账号连续刷新、电视端设置切换和 Apple TV 真机长列表仍待验收，当前没有配对真机。 |
| 2026-11-19 | TV-19 | 进行中 | WebDAV 连接信息保存在独立 Keychain 项。接入 `PROPFIND`、`MKCOL`、`PUT` 和 `GET`，复用 Dart 的 `simple_live_app/backup.zip` 路径，支持新版 v2–v4 配置和旧版拆分 JSON。用 Dart archive 4.0.9 生成两个 ZIP，Swift 在本机 WsgiDAV 通过认证、上传、下载和恢复。Dart `ZipDecoder().decodeBytes(..., verify: true)` 反向验证 Swift ZIP 并读取历史。隔离 `SyncArchiveTests` 2 项通过，覆盖类别选择、损坏 ZIP 和时间往返。待电视端配置、恢复确认和真机验收。 |
| 2026-11-19 | TV-08、TV-17、TV-18、TV-19 | 进行中 | 对齐 Dart 快手无过期时间时的 `0` 值和数字字符串写法；修正房间号布尔值校验、图片地址及取消提示。隔离 `swift test --package-path /private/tmp/sl-sync-package` 通过新增快手过期时间断言及归档微秒时间往返断言。 |
| 2026-11-19 | TV-15 | 待验收 | 设置首页接入播放、弹幕、关注、多屏、账号、关于六区。频道轮播放在播放区，账号与关于链接到各自已交付页面。Apple TV 4K 模拟器隔离 UI 工程 `xcodebuild test -only-testing:MultiRoomUITests/MultiRoomFlowUITests/testFollowEntryAndSettingsHome` 遥控测试通过，确认进入多屏与播放设置。新版播放器与多屏参数专项测试复跑通过，待 Apple TV 真机复验。 |
| 2026-11-19 | TV-02 / TV-13 | 进行中／待验收 | 把确认、取消与来源切换放在同一焦点行，使用可在房内弹层打开的平台菜单。隔离 UI 工程 `xcodebuild test -only-testing:MultiRoomUITests/MultiRoomFlowUITests/testFollowEntryAndSettingsHome` 通过；首页遥控流程已验证从关注和历史各选一路后进入双屏。临时 `MultiRoomProviderProbeTests` 在 Apple TV 模拟器验证真实 B 站和斗鱼直播搜索、跨平台识别分享文本中的 B 站链接、斗鱼房号解析和去重，1 项通过。其余站点及真机仍待抽验。 |
| 2026-11-19 | TV-17、TV-18 | 进行中 | 拒绝同一来源重叠分块和布尔值编号，远程房间有多个发送方时要求分块提供来源标识。隔离运行 `swift test --package-path /private/tmp/sl-sync-package` 共 14 项通过，新增重叠序列不混合的回归测试。使用本机 HTTP CONNECT 代理连接国内站点，Dart 两段历史收到回执，Swift 持久化成功。 |
| 2026-11-19 | TV-09 | 待验收 | 完整快照 `e9603abd` 加列表焦点修复，离线执行 `xcodebuild test-without-building -skip-testing:SimpleLiveTVOSTests/ProviderSmokeTests -skip-testing:SimpleLiveTVOSTests/PlaybackAcceptanceTests`，71 项通过、1 项多屏联网用例跳过、0 失败。临时遥控工程的 `testTV09RoomControlsAndPreservedChoices` 与 `testTV09VolumeFavoritesAndChannelSheets` 分别通过，覆盖暂停、刷新保留清晰度和指定线路、打开设置调至 90%、打开收藏列表，以及从频道列表选房并完成换台。完整引擎专项验证静音、30% 音量、继续播放和线路回退；五个平台真实直播在模拟器起播。线路回退后实体 Play/Pause 首轮未观察到状态变化，隔离复验通过，现象及复验已交给多屏与播放对话。Apple TV 未配对，真实遥控和实播控制仍待验收。 |
| 2026-11-19 | TV-02 | 待验收 | 首页增加「数据同步」，使用同一导航栈与多屏选房并排。Apple TV 4K（tvOS 26.5）`xcodebuild test -only-testing:SyncUITests/SyncNavigationTests/testHomeSyncAndMultiRoomShareTheShortcutRow` 遥控打开同步、返回恢复焦点、转去多屏均通过。待真机复验首页入口与进房返回焦点。 |
| 2026-11-19 | TV-08 | 待验收 | 历史页加入「导入历史」，远程、局域网和 WebDAV 入口固定为历史类别。共用 `SyncProfileTests` 通过导入、持久化、未选类别和时间去重验证。待电视端覆盖确认及真机复验。 |
| 2026-11-19 | TV-17 | 待验收 | 远程页接入站点及代理输入、房间码和二维码、倒计时、接收结果与覆盖确认。Apple TV 模拟器遥控创建国内站点房间并显示房间码通过；Dart 发送端验证两站点和 HTTP CONNECT 路径。待真机扫码、到期及真实账号凭据验收。 |
| 2026-11-19 | TV-18 | 待验收 | 局域网页打开时监听并展示 IPv4 地址、二维码、回执结果；离开或切到后台停止接收。Apple TV 模拟器遥控进入、地址及二维码显示通过，`SyncLANTests` 通过。待真机局域网权限、跨设备 UDP 广播及手机扫码验收。 |
| 2026-11-19 | TV-19 | 待验收 | WebDAV 页提供验证并保存连接、移除凭据、上传和下载恢复的阶段进度、上次成功时间与类别选择。独立新旧 Dart ZIP 和本机真实 WsgiDAV 互通通过，Apple TV 模拟器编译通过。待 Apple TV 真机输入凭据、远端上传和选择性覆盖恢复验收。 |
| 2026-11-19 | TV-09 / TV-10 / TV-14 | 待验收 | 单房间响应实体播放键后在控制栏显示状态，定时关闭弹层后把焦点交给「返回」，从房内确认多屏时先释放原播放器。隔离 UI 工程 `xcodebuild test` 的 `testSinglePlayerRemotePauseAfterFallback` 与 `testSinglePlayerSleepDismissesSheetAndFocusesReturn` 通过，覆盖无效首线路回退后用实体键暂停、前后台保留暂停和定时到期后的焦点。待真机复验。 |

## 对照入口

- [Dart TV 路由](../../simple_live_tv_app/lib/routes/app_pages.dart)
- [Dart TV 基础能力实施记录](../TV端基础能力实施记录.md)
- [Dart TV 多屏界面实施记录](../TV多屏界面实施记录.md)
- [Swift tvOS 入口](../../simple_live_tvos_native/Sources/HomeView.swift)
