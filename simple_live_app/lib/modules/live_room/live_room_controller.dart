import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/desktop_startup_args.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/platform_utils.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/live_room/player/ohos_playback_signal_adapter.dart';
import 'package:simple_live_app/modules/live_room/player/ohos_line_failover_policy.dart';
import 'package:simple_live_app/modules/live_room/player/ohos_playback_profile_policy.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';
import 'package:simple_live_app/modules/live_room/player/ohos_video_player.dart';
import 'package:simple_live_app/modules/live_room/live_room_hold_preview.dart';
import 'package:simple_live_app/modules/live_room/widgets/live_contribution_rank_panel.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_playback_recovery.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_player_controller.dart';
import 'package:simple_live_app/modules/multi_room/player_mutation_queue.dart';
import 'package:simple_live_app/modules/settings/danmu_settings_page.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/background_playback_service.dart';
import 'package:simple_live_app/services/current_room_service.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/kuaishou_account_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/live_latency_telemetry_service.dart';
import 'package:simple_live_app/services/live_link_health_collector.dart'
    show didLivePlaybackHostChange;
import 'package:simple_live_app/services/live_link_health_models.dart';
import 'package:simple_live_app/services/mpv_live_latency_chase_service.dart';
import 'package:simple_live_app/services/mpv_options_service.dart';
import 'package:simple_live_app/services/ohos_network_service.dart';
import 'package:simple_live_app/services/ohos_document_service.dart';
import 'package:simple_live_app/widgets/filter_button.dart';
import 'package:simple_live_app/widgets/desktop_refresh_button.dart';
import 'package:simple_live_app/widgets/follow_user_item.dart';
import 'package:simple_live_app/widgets/immersive_volume_slider.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';
import 'package:simple_live_app/widgets/status/app_empty_widget.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:video_player/video_player.dart';
import 'package:window_manager/window_manager.dart';

export 'live_room_auto_quality_buffer_tracker.dart'
    show LiveRoomAutoQualityBufferTracker;
export 'ohos_playback_degrade_evidence.dart' show OhosPlaybackDegradeEvidence;
export 'ohos_reconnect_confirmation.dart'
    show OhosReconnectConfirmation, OhosReconnectOutcome;

import 'live_room_auto_quality_buffer_tracker.dart';
import 'ohos_playback_degrade_evidence.dart';
import 'ohos_reconnect_confirmation.dart';
import 'kuaishou_playback_recovery_tracker.dart';

@visibleForTesting
bool shouldResumeLiveRoomAfterInlineMultiRoom({
  required bool playing,
  required bool buffering,
}) {
  return playing || buffering;
}

@visibleForTesting
bool shouldAcceptOfflineRoomRefresh({
  required bool playbackActive,
  required int consecutiveOfflineReports,
  int requiredReports = 3,
}) {
  return !playbackActive && consecutiveOfflineReports >= requiredReports;
}

/// 在线状态轮询的退避间隔（S2-T1）。
///
/// [state] 为当前房间直播状态，[failures] 为连续失败（unknown）次数。
/// 规则：
/// - live：10s（恢复常态，重置退避）；
/// - offline：45s（低频确认，配合离线遮罩）；
/// - unknown/失败：按 10s → 30s → 60s → 120s → 240s 指数增长，封顶 300s。
@visibleForTesting
Duration resolveOnlineRefreshDelay(
  LiveStatusState state,
  int failures,
) {
  if (state == LiveStatusState.live) {
    return const Duration(seconds: 10);
  }
  if (state == LiveStatusState.offline) {
    return const Duration(seconds: 45);
  }
  final step = (failures + 1).clamp(0, 6).toInt();
  // step=1 -> 10s, 2 -> 30s, 3 -> 60s, 4 -> 120s, 5 -> 240s, 6+ -> 300s(封顶)
  final delaySeconds = step <= 1 ? 10 : 15 * (1 << (step - 1));
  final capped = delaySeconds > 300 ? 300 : delaySeconds;
  return Duration(seconds: capped);
}

/// 根据本次状态响应更新连续 unknown/失败次数。
///
/// 请求异常同样会转换为 [LiveStatusState.unknown] 后走此入口，因此调用方
/// 不应在 catch 中再次累加。明确 live 会恢复基础间隔；offline 使用独立的
/// 45 秒复核间隔，不参与 unknown 退避计数。
@visibleForTesting
int resolveOnlineRefreshFailureCount({
  required LiveStatusState incomingState,
  required int currentFailures,
}) {
  if (incomingState == LiveStatusState.live) {
    return 0;
  }
  if (incomingState == LiveStatusState.unknown) {
    return currentFailures + 1;
  }
  return currentFailures;
}

String formatKuaishouRecoveryCountdown(int totalSeconds) {
  final seconds = totalSeconds < 0 ? 0 : totalSeconds;
  final minutesPart = seconds ~/ 60;
  final secondsPart = seconds % 60;
  return '$minutesPart:${secondsPart.toString().padLeft(2, '0')}';
}

@visibleForTesting
bool shouldAutoRetryKuaishouDeviceRecovery({
  required bool roomDisposed,
  required bool armed,
  required String? recoveryRoomKey,
  required String currentRoomKey,
}) {
  return !roomDisposed &&
      armed &&
      recoveryRoomKey != null &&
      recoveryRoomKey == currentRoomKey;
}

/// Returns the minute-scale Kuaishou recheck interval while playback is
/// healthy. The caller supplies the jitter so the policy remains testable.
@visibleForTesting
Duration resolveKuaishouStableRefreshDelay({int jitterSeconds = 0}) {
  final boundedJitter = jitterSeconds.clamp(-30, 30).toInt();
  return Duration(seconds: 150 + boundedJitter);
}

/// A buffering player is active, but not stable enough to suppress normal
/// recovery behaviour or be treated as a healthy Kuaishou session.
@visibleForTesting
bool isLiveRoomPlaybackStable({
  required bool initialized,
  required bool playing,
  required bool buffering,
  required bool hasError,
}) {
  return initialized && playing && !buffering && !hasError;
}

/// Keeps the selected Kuaishou quality across a fresh detail snapshot. Names
/// survive reordering; the old index is only a fallback for renamed entries.
@visibleForTesting
int resolveKuaishouRecoveryQualityIndex({
  required List<String> qualities,
  required String? previousQualityName,
  required int previousQualityIndex,
}) {
  assert(qualities.isNotEmpty);
  if (previousQualityName != null && previousQualityName.isNotEmpty) {
    final matchingIndex = qualities.indexOf(previousQualityName);
    if (matchingIndex >= 0) {
      return matchingIndex;
    }
  }
  return previousQualityIndex.clamp(0, qualities.length - 1).toInt();
}

/// Keeps a Kuaishou CDN selection stable when signed URLs are refreshed and
/// the platform returns the lines in a different order.
@visibleForTesting
int resolveKuaishouRecoveryLineIndex({
  required List<String> urls,
  required String? previousUrl,
  required int fallbackIndex,
}) {
  assert(urls.isNotEmpty);
  final previousSignature = liveRoomLineMemorySignature(previousUrl);
  if (previousSignature != null) {
    final matchingIndex = urls.indexWhere(
      (url) => liveRoomLineMemorySignature(url) == previousSignature,
    );
    if (matchingIndex >= 0) {
      return matchingIndex;
    }
  }
  return fallbackIndex.clamp(0, urls.length - 1).toInt();
}

@immutable
class RoomLiveRefreshDecision {
  final LiveStatusState state;
  final int consecutiveOfflineReports;
  final bool liveStatus;

  const RoomLiveRefreshDecision({
    required this.state,
    required this.consecutiveOfflineReports,
    required this.liveStatus,
  });
}

@visibleForTesting
RoomLiveRefreshDecision resolveRoomLiveRefresh({
  required LiveStatusState currentState,
  required LiveStatusState incomingState,
  required int consecutiveOfflineReports,
  required bool currentLiveStatus,
  required bool playbackActive,
  int requiredOfflineReports = 3,
}) {
  if (incomingState == LiveStatusState.live) {
    return const RoomLiveRefreshDecision(
      state: LiveStatusState.live,
      consecutiveOfflineReports: 0,
      liveStatus: true,
    );
  }
  if (incomingState == LiveStatusState.unknown) {
    return RoomLiveRefreshDecision(
      state: currentState,
      consecutiveOfflineReports: currentState == LiveStatusState.offline
          ? consecutiveOfflineReports
          : 0,
      liveStatus: currentLiveStatus,
    );
  }
  if (playbackActive) {
    return RoomLiveRefreshDecision(
      state: currentState,
      consecutiveOfflineReports: 0,
      liveStatus: currentLiveStatus,
    );
  }

  final reports = consecutiveOfflineReports + 1;
  if (reports >= requiredOfflineReports) {
    return RoomLiveRefreshDecision(
      state: LiveStatusState.offline,
      consecutiveOfflineReports: reports,
      liveStatus: false,
    );
  }
  return RoomLiveRefreshDecision(
    state: currentState,
    consecutiveOfflineReports: reports,
    liveStatus: currentLiveStatus,
  );
}

/// A refresh snapshot is safe to publish only after its state transition has
/// been accepted. This keeps an active room's metadata intact while explicit
/// offline reports are still being confirmed.
@visibleForTesting
bool shouldCommitRoomDetailRefresh({
  required LiveStatusState incomingState,
  required RoomLiveRefreshDecision decision,
}) {
  return incomingState != LiveStatusState.unknown &&
      incomingState == decision.state;
}

/// Keeps known Kuaishou presentation metadata when a fresh playback/status
/// snapshot omits it. Session-bound data always comes from [incoming], so
/// account cookies, danmaku credentials, and playback URLs are never mixed.
@visibleForTesting
LiveRoomDetail mergeKuaishouRoomDetailMetadata({
  required LiveRoomDetail current,
  required LiveRoomDetail incoming,
}) {
  String prefer(String next, String previous) =>
      next.trim().isNotEmpty ? next : previous;
  String? preferNullable(String? next, String? previous) =>
      next?.trim().isNotEmpty == true ? next : previous;

  return LiveRoomDetail(
    roomId: prefer(incoming.roomId, current.roomId),
    title: prefer(incoming.title, current.title),
    cover: prefer(incoming.cover, current.cover),
    userName: prefer(incoming.userName, current.userName),
    userAvatar: prefer(incoming.userAvatar, current.userAvatar),
    online: incoming.online,
    introduction: preferNullable(incoming.introduction, current.introduction),
    notice: preferNullable(incoming.notice, current.notice),
    status: incoming.status,
    liveStatusState: incoming.liveStatusState,
    data: incoming.data,
    danmakuData: incoming.danmakuData,
    url: prefer(incoming.url, current.url),
    isRecord: incoming.isRecord,
    showTime: preferNullable(incoming.showTime, current.showTime),
    categoryId: preferNullable(incoming.categoryId, current.categoryId),
    categoryName: preferNullable(incoming.categoryName, current.categoryName),
    categoryParentId:
        preferNullable(incoming.categoryParentId, current.categoryParentId),
    categoryParentName: preferNullable(
      incoming.categoryParentName,
      current.categoryParentName,
    ),
    categoryPic: preferNullable(incoming.categoryPic, current.categoryPic),
  );
}

@immutable
class LiveRoomQualityPreference {
  final int? qualityIndex;
  final int? lineIndex;
  final String? lineSignature;
  final bool qualityLocked;

  const LiveRoomQualityPreference({
    required this.qualityIndex,
    required this.lineIndex,
    this.lineSignature,
    required this.qualityLocked,
  });

  @visibleForTesting
  factory LiveRoomQualityPreference.fromStoredValue(Object? value) {
    if (value is! Map) {
      return const LiveRoomQualityPreference(
        qualityIndex: null,
        lineIndex: null,
        qualityLocked: false,
      );
    }
    final quality = value["quality"];
    final line = value["line"];
    final lineSignature = value["lineSignature"];
    final storedLocked = value["qualityLocked"];
    return LiveRoomQualityPreference(
      qualityIndex: quality is num ? quality.toInt() : null,
      lineIndex: line is num ? line.toInt() : null,
      lineSignature: lineSignature is String && lineSignature.isNotEmpty
          ? lineSignature
          : null,
      // Before qualityLocked was persisted, a stored quality represented the
      // user's remembered selection. Preserve that legacy behaviour once.
      qualityLocked: storedLocked is bool ? storedLocked : quality is num,
    );
  }
}

/// Produces a stable line-memory identity without retaining a fragile list
/// index. The tier, rather than the exact protocol, is intentional: FLV and
/// RTMP share the same low-latency preference.
@visibleForTesting
String? liveRoomLineMemorySignature(String? url) {
  final uri = Uri.tryParse(url?.trim() ?? '');
  final host = uri?.host.toLowerCase();
  if (host == null || host.isEmpty) {
    return null;
  }
  final tier = classifyLiveStreamProtocol(url).latencyPriority;
  return '$host|$tier';
}

@visibleForTesting
int? resolveRememberedLiveRoomLineIndex({
  required List<String> urls,
  required LiveRoomQualityPreference preference,
}) {
  final bestLineIndices = lowestLatencyLineIndices(urls);
  final signature = preference.lineSignature;
  if (signature != null) {
    for (final index in bestLineIndices) {
      if (liveRoomLineMemorySignature(urls[index]) == signature) {
        return index;
      }
    }
    return null;
  }

  // Legacy values only contain an index. Keep the old behaviour until the
  // next manual selection migrates it to a host+tier signature.
  final legacyIndex = preference.lineIndex;
  if (legacyIndex != null && bestLineIndices.contains(legacyIndex)) {
    return legacyIndex;
  }
  return null;
}

String liveRoomLineProtocolLabel(String url) {
  final protocol = classifyLiveStreamProtocol(url);
  return switch (protocol) {
    LiveStreamProtocol.flv => 'FLV',
    LiveStreamProtocol.hls => 'HLS',
    LiveStreamProtocol.fmp4 => 'fMP4',
    LiveStreamProtocol.rtmp => 'RTMP',
    LiveStreamProtocol.unknown => '未知协议',
  };
}

@visibleForTesting
int resolveInitialLiveRoomQualityIndex({
  required int qualityCount,
  required int qualityLevel,
  required LiveRoomQualityPreference preference,
}) {
  assert(qualityCount > 0);
  final remembered = preference.qualityIndex;
  if (preference.qualityLocked &&
      remembered != null &&
      remembered >= 0 &&
      remembered < qualityCount) {
    return remembered;
  }
  if (qualityLevel == 2) {
    return 0;
  }
  if (qualityLevel == 0) {
    return qualityCount - 1;
  }
  return (qualityCount / 2).floor();
}

@visibleForTesting
bool isCurrentLiveRoomPlaybackRequest({
  required int roomGeneration,
  required int expectedRoomGeneration,
  required int requestRevision,
  required int latestRequestRevision,
}) {
  return roomGeneration == expectedRoomGeneration &&
      requestRevision == latestRequestRevision;
}

/// The small state machine used by OHOS' post-first-frame line selection.
///
/// This is deliberately separate from the playback state machine.  It only
/// decides whether a result from a background TCP probe may still be applied;
/// source assignment, recovery and native player lifecycle remain owned by the
/// playback controller.
enum OhosAutoLineSelectionStatus {
  idle,
  measuring,
  switched,
  skipped,
  stale,
  failed,
}

@immutable
class OhosAutoLineSelectionDiagnostic {
  const OhosAutoLineSelectionDiagnostic({
    required this.status,
    required this.reason,
    required this.roomGeneration,
    required this.playbackRequestRevision,
    required this.playerGeneration,
    required this.manualLineSelectionRevision,
    required this.candidateCount,
    this.initialLineIndex,
    this.selectedLineIndex,
    this.measuredLineIndex,
  });

  final OhosAutoLineSelectionStatus status;
  final String reason;
  final int roomGeneration;
  final int playbackRequestRevision;
  final int playerGeneration;
  final int manualLineSelectionRevision;
  final int candidateCount;
  final int? initialLineIndex;
  final int? selectedLineIndex;

  /// Candidate-relative result returned by the TCP probe. This is deliberately
  /// an index, never a URL or host name.
  final int? measuredLineIndex;
}

/// Returns lines in the same protocol family as the active line.
///
/// The URL values stay in the caller's private list; this helper only returns
/// indexes so diagnostics can remain URL-free. Matching the active protocol
/// prevents a background probe from changing the user's explicitly selected
/// protocol family.
@visibleForTesting
List<int> resolveOhosAutoLineCandidateIndices({
  required List<String> urls,
  required int currentLineIndex,
}) {
  if (currentLineIndex < 0 || currentLineIndex >= urls.length) {
    return const [];
  }
  final activeProtocol = classifyLiveStreamProtocol(urls[currentLineIndex]);
  return [
    for (var index = 0; index < urls.length; index += 1)
      if (classifyLiveStreamProtocol(urls[index]) == activeProtocol) index,
  ];
}

/// Accepts a completed OHOS line probe only while every captured playback
/// identity still points at the same room and native player.
@visibleForTesting
bool shouldAcceptOhosAutoLineSelection({
  required int roomGeneration,
  required int expectedRoomGeneration,
  required int playbackRequestRevision,
  required int latestPlaybackRequestRevision,
  required int playerGeneration,
  required int currentPlayerGeneration,
  required int manualLineSelectionRevision,
  required int latestManualLineSelectionRevision,
  required bool hasActivePlaybackSession,
  required bool playerRecovering,
  required bool autoLineSwitchAlreadyCompleted,
}) {
  return roomGeneration == expectedRoomGeneration &&
      playbackRequestRevision == latestPlaybackRequestRevision &&
      playerGeneration == currentPlayerGeneration &&
      manualLineSelectionRevision == latestManualLineSelectionRevision &&
      hasActivePlaybackSession &&
      !playerRecovering &&
      !autoLineSwitchAlreadyCompleted;
}

class _HoldPreviewAudioSnapshot {
  const _HoldPreviewAudioSnapshot({
    required this.volume,
    required this.muted,
  });

  final double volume;
  final bool muted;
}

class LiveRoomController extends PlayerController
    with WidgetsBindingObserver, WindowListener {
  @override
  String get liveLinkHealthTarget => '${rxSite.value.id}/${rxRoomId.value}';

  static const volumeSliderDialogTag = "live_room_volume_slider";
  final Site pSite;
  final String pRoomId;
  final bool initialDesktopSidePanelCollapsed;
  late LiveDanmaku liveDanmaku;
  LiveRoomController({
    required this.pSite,
    required this.pRoomId,
    this.initialDesktopSidePanelCollapsed = false,
  }) {
    rxSite = pSite.obs;
    rxRoomId = pRoomId.obs;
    desktopSidePanelCollapsed.value = initialDesktopSidePanelCollapsed;
    liveDanmaku = site.liveSite.getDanmaku();
  }

  late Rx<Site> rxSite;
  Site get site => rxSite.value;
  late Rx<String> rxRoomId;
  String get roomId => rxRoomId.value;

  Rx<LiveRoomDetail?> detail = Rx<LiveRoomDetail?>(null);
  var online = 0.obs;
  var followed = false.obs;
  var liveStatus = false.obs;
  final roomLiveState = LiveStatusState.unknown.obs;
  final offlineConfirmations = 0.obs;
  final waitingForPlaybackUrl = false.obs;
  bool _kuaishouNoCookieHintShown = false;

  /// Kuaishou runs without any account cookie (anonymous device mode): the
  /// site falls back to a dummy danmaku client and playback URLs may be
  /// unavailable, so the room must tell the user instead of spinning forever.
  bool get _kuaishouNoCookie =>
      site.id == Constant.kKuaishou &&
      (!Get.isRegistered<KuaishouAccountService>() ||
          KuaishouAccountService.instance.activeSession == null);

  /// Shown once per room load: kuaishou is live but playback URLs never
  /// arrive, most likely because the anonymous (cookie-less) session is
  /// not entitled to stream URLs.
  void _showKuaishouNoCookiePlaybackHint() {
    if (!_kuaishouNoCookie || _kuaishouNoCookieHintShown) {
      return;
    }
    _kuaishouNoCookieHintShown = true;
    SmartDialog.showToast("快手未登录（无 Cookie），可能无法获取播放地址，登录后重试");
  }
  RxList<LiveSuperChatMessage> superChats = RxList<LiveSuperChatMessage>();
  RxList<LiveContributionRankItem> contributionRanks =
      RxList<LiveContributionRankItem>();
  RxList<LiveRepeatedDanmuSummary> liveEventFlows =
      RxList<LiveRepeatedDanmuSummary>();
  bool _autoSwitchingRoom = false;
  bool _roomSwitching = false;
  Site? _pendingRoomSite;
  String? _pendingRoomId;
  var contributionRankLoading = false.obs;
  var contributionRankFetched = false.obs;
  Rx<String?> contributionRankError = Rx<String?>(null);
  Rx<DateTime?> contributionRankUpdatedAt = Rx<DateTime?>(null);
  RxDouble danmakuViewportHeight = 0.0.obs;
  final liveRoomFollowFilterMode = 0.obs;
  final liveRoomSelectedPanelKey = "chat".obs;
  final desktopSidePanelCollapsed = false.obs;
  RxSet<String> tempMutedUsers = <String>{}.obs;
  bool get supportsContributionRank => const {
        Constant.kBiliBili,
        Constant.kDouyu,
        Constant.kDouyin,
      }.contains(site.id);

  void toggleDesktopSidePanel() {
    desktopSidePanelCollapsed.value = !desktopSidePanelCollapsed.value;
  }

  /// 聊天列表滚动控制器
  final ScrollController scrollController = ScrollController();

  /// 直播间右侧关注列表滚动控制器
  final ScrollController liveRoomFollowScrollController = ScrollController();

  /// 直播间弹窗关注列表滚动控制器
  final ScrollController liveRoomFollowDialogScrollController =
      ScrollController();

  /// 直播间弹窗历史列表滚动控制器
  final ScrollController liveRoomHistoryScrollController = ScrollController();

  /// 直播间弹窗同类推荐列表滚动控制器
  final ScrollController liveRoomRecommendationScrollController =
      ScrollController();

  static const Duration _holdPreviewLingerDuration = Duration(seconds: 3);
  static const Duration _holdPreviewLoadTimeout = Duration(seconds: 10);
  static const bool _holdPreviewEnabledOnIos = bool.fromEnvironment(
    "SL_ENABLE_IOS_HOLD_PREVIEW",
    defaultValue: true,
  );
  final PlayerMutationQueue _holdPreviewMutations = PlayerMutationQueue();
  final MultiRoomPlaybackRecoveryCoordinator _holdPreviewRecovery =
      const MultiRoomPlaybackRecoveryCoordinator();
  MultiRoomPlayerController? _holdPreviewPlayer;
  String? _holdPreviewPlayerTag;
  MultiRoomItem? _holdPreviewItem;
  OverlayEntry? _holdPreviewOverlay;
  Timer? _holdPreviewLingerTimer;
  DateTime? _holdPreviewLingerDeadline;
  LiveRoomHoldPreviewPhase _holdPreviewPhase = LiveRoomHoldPreviewPhase.closed;
  _HoldPreviewAudioSnapshot? _holdPreviewAudioSnapshot;
  bool _holdPreviewOwnsAudio = false;
  bool _holdPreviewMainWasPlaying = false;
  bool _holdPreviewPromotingMain = false;
  bool _holdPreviewClosing = false;
  int _holdPreviewRevision = 0;

  /// 聊天消息列表
  RxList<LiveMessage> messages = RxList<LiveMessage>();

  /// 清晰度列表
  RxList<LivePlayQuality> qualites = RxList<LivePlayQuality>();

  /// 当前清晰度索引
  var currentQuality = -1;
  var currentQualityInfo = "".obs;

  /// 画质是否被手动锁定（选"自动"时 false，选具体画质时 true）。
  final qualityLocked = false.obs;
  int _qualitySelectionRevision = 0;

  void markQualitySelectionAsManual() {
    _qualitySelectionRevision += 1;
    // Invalidate a probe immediately, before the asynchronous quality request
    // starts.  The request revision is still advanced again by getPlayUrl.
    if (Utils.isOhos) {
      _playbackRequestRevision += 1;
    }
  }

  /// 选"自动"：解锁画质，回到按 qualityLevel 设置的自动档。
  Future<void> useAutomaticQuality() async {
    final selectionRevision = ++_qualitySelectionRevision;
    if (Utils.isOhos) {
      _playbackRequestRevision += 1;
    }
    qualityLocked.value = false;
    saveQualityMemory();
    _autoQualityBufferTracker.reset();
    await reloadQuality(expectedSelectionRevision: selectionRevision);
  }

  /// 按当前 qualityLevel 设置重新加载画质。
  Future<void> reloadQuality({int? expectedSelectionRevision}) async {
    if (qualites.isEmpty) return;
    var qualityLevel = await getQualityLevel();
    if (expectedSelectionRevision != null &&
        expectedSelectionRevision != _qualitySelectionRevision) {
      return;
    }
    int target;
    if (qualityLevel == 2) {
      target = 0;
    } else if (qualityLevel == 0) {
      target = qualites.length - 1;
    } else {
      target = (qualites.length / 2).floor();
    }
    if (target != currentQuality) {
      currentQuality = target;
      currentQualityInfo.value = qualites[target].quality;
      await getPlayUrl(userInitiatedQualityChange: true);
    }
  }

  LiveRoomQualityPreference _loadQualityPreference() {
    try {
      final raw = LocalStorageService.instance
          .getValue(LocalStorageService.kRoomQualityMemory, "");
      if (raw.isEmpty) {
        return const LiveRoomQualityPreference(
          qualityIndex: null,
          lineIndex: null,
          qualityLocked: false,
        );
      }
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return LiveRoomQualityPreference.fromStoredValue(data[site.id]);
    } catch (_) {}
    return const LiveRoomQualityPreference(
      qualityIndex: null,
      lineIndex: null,
      qualityLocked: false,
    );
  }

  /// 保存当前站点画质记忆；线路只在用户主动切换时写入。
  void saveQualityMemory({bool saveLine = false}) {
    try {
      final raw = LocalStorageService.instance
          .getValue(LocalStorageService.kRoomQualityMemory, "");
      Map<String, dynamic> data;
      if (raw.isNotEmpty) {
        data =
            (jsonDecode(raw) as Map<String, dynamic>).cast<String, dynamic>();
      } else {
        data = <String, dynamic>{};
      }
      final siteData = (data[site.id] as Map?)?.cast<String, dynamic>() ?? {};
      siteData["qualityLocked"] = qualityLocked.value;
      if (qualityLocked.value && currentQuality >= 0) {
        siteData["quality"] = currentQuality;
      } else {
        siteData.remove("quality");
      }
      if (saveLine) {
        // New values must not keep a list index: URL ordering and count can
        // change between room entries. Keep old indexes only until a manual
        // selection provides a signature and performs the migration.
        siteData.remove("line");
        final lineUrl =
            currentLineIndex >= 0 && currentLineIndex < playUrls.length
                ? playUrls[currentLineIndex]
                : null;
        final signature = liveRoomLineMemorySignature(lineUrl);
        if (signature == null) {
          siteData.remove("lineSignature");
        } else {
          siteData["lineSignature"] = signature;
        }
      }
      data[site.id] = siteData;
      LocalStorageService.instance.setValue(
        LocalStorageService.kRoomQualityMemory,
        jsonEncode(data),
      );
    } catch (_) {}
  }

  /// 播放线路列表
  RxList<String> playUrls = RxList<String>();

  Map<String, String>? playHeaders;

  /// Rebuilds the native HarmonyOS player when the URL or line changes.
  final RxInt ohosPlayerRevision = 0.obs;

  /// Room generation passed to the OHOS player profile and line-selection
  /// callbacks. It changes only when the room changes.
  int get ohosPlaybackSessionGeneration => _loadGeneration;

  final RxString ohosPlaybackProfileStatus = 'stable'.obs;
  final RxString ohosPlaybackProfileReason = 'stableRequested'.obs;

  void updateOhosPlaybackProfileDecision(
    int sessionGeneration,
    int playerGeneration,
    OhosPlaybackProfileDecision decision,
  ) {
    if (!Utils.isOhos ||
        _roomDisposed ||
        sessionGeneration != _loadGeneration ||
        playerGeneration != ohosPlayerRevision.value) {
      return;
    }
    ohosPlaybackProfileStatus.value = decision.profile.name;
    ohosPlaybackProfileReason.value = decision.reason.name;
  }

  @override
  String get ohosPlaybackProfileDiagnostic =>
      '${ohosPlaybackProfileStatus.value} (${ohosPlaybackProfileReason.value})';

  /// 当前播放线路索引
  var currentLineIndex = -1;
  var currentLineInfo = "".obs;

  @override
  String get currentNetworkDiagnosePlaybackUrl {
    if (currentLineIndex < 0 || currentLineIndex >= playUrls.length) {
      return '';
    }
    final url = playUrls[currentLineIndex];
    return AppSettingsController.instance.playerForceHttps.value
        ? url.replaceAll('http://', 'https://')
        : url;
  }

  String lineDisplayName(int index) {
    final lineName = "线路${index + 1}";
    if (index < 0 || index >= playUrls.length) {
      return lineName;
    }
    return '$lineName ${liveRoomLineProtocolLabel(playUrls[index])}';
  }

  /// 自动退出倒计时，单位秒
  var countdown = 60.obs;

  Timer? autoExitTimer;
  DateTime? _autoExitDeadline;
  bool _autoExitCompleting = false;

  /// 设置的自动关闭时长，单位分钟
  var autoExitMinutes = 60.obs;

  /// 是否已请求延迟自动关闭
  var delayAutoExit = false.obs;

  /// 是否启用自动关闭
  var autoExitEnable = false.obs;

  /// 是否禁用聊天自动滚动
  /// - 用户手动上拉聊天列表后，不再自动滚到底部
  var disableAutoScroll = false.obs;

  /// 应用是否处于后台
  var isBackground = false;

  bool get _allowBackgroundPlayback =>
      AppSettingsController.instance.allowBackgroundPlayback.value;

  /// 直播间加载是否失败
  var loadError = false.obs;
  Object? error;
  StackTrace? errorStackTrace;
  final kuaishouRecoveryRemainingSeconds = 0.obs;
  final kuaishouDeviceRecoveryAvailable = false.obs;
  final kuaishouDeviceRecoveryArmed = false.obs;
  Timer? _kuaishouDeviceRecoveryTimer;
  String? _kuaishouDeviceRecoveryRoomKey;
  KuaishouAccountSlot? _kuaishouDeviceRecoverySlot;

  bool get showKuaishouDeviceRecovery =>
      error is KuaishouRateLimitError &&
      (kuaishouDeviceRecoveryAvailable.value ||
          kuaishouDeviceRecoveryArmed.value);

  bool get kuaishouRefreshBlocked =>
      error is KuaishouRateLimitError &&
      kuaishouRecoveryRemainingSeconds.value > 0;

  String get kuaishouRecoveryHint {
    final remaining = kuaishouRecoveryRemainingSeconds.value;
    if (kuaishouDeviceRecoveryArmed.value && remaining > 0) {
      return '设备会话已重建，${formatKuaishouRecoveryCountdown(remaining)} 后自动重试';
    }
    if (remaining > 0) {
      return '请求冷却中，剩余 ${formatKuaishouRecoveryCountdown(remaining)}';
    }
    if (error is KuaishouRateLimitError &&
        !kuaishouDeviceRecoveryAvailable.value) {
      return '今天已重建过设备会话，请稍后再试或重新登录';
    }
    return '';
  }

  // 开播时长展示状态
  var liveDuration = "00:00:00".obs;
  Timer? _liveDurationTimer;
  StreamSubscription<Duration>? _positionSubscription;
  Duration _lastKnownPlayerPosition = Duration.zero;
  Duration? _positionBeforeBackground;
  bool? _ohosWasPlayingBeforeBackground;
  bool? _wasPlayingBeforeBackground;
  DateTime? _backgroundedAt;
  Duration? _positionBeforeWindowBlur;
  bool? _wasPlayingBeforeWindowBlur;
  DateTime? _windowBlurredAt;
  Completer<void>? _playerReopenCompleter;
  bool _roomDisposed = false;
  int _loadGeneration = 0;
  int _playbackRequestRevision = 0;
  int _manualLineSelectionRevision = 0;
  int? _ohosPlayerLoadGeneration;
  int? _ohosPlayerRequestRevision;
  bool _ohosPlayerStartedDuringRecovery = false;
  bool _ohosAutoLineSelectionConsumed = false;
  bool _ohosAutoLineSwitchCompleted = false;
  int? _ohosAutoLineSelectionScheduledPlayerGeneration;
  final Rx<OhosAutoLineSelectionDiagnostic> ohosAutoLineSelectionDiagnostic =
      Rx<OhosAutoLineSelectionDiagnostic>(
    const OhosAutoLineSelectionDiagnostic(
      status: OhosAutoLineSelectionStatus.idle,
      reason: 'not_started',
      roomGeneration: -1,
      playbackRequestRevision: -1,
      playerGeneration: -1,
      manualLineSelectionRevision: -1,
      candidateCount: 0,
    ),
  );
  final Set<String> _superChatFingerprints = <String>{};
  LiveRepeatedDanmuAggregator _liveEventFlowAggregator =
      LiveRepeatedDanmuAggregator();
  final Queue<String> _recentDanmuFingerprints = Queue<String>();
  final Map<String, int> _recentDanmuCounts = <String, int>{};
  int _recentDanmuEventsSincePrune = 0;
  final Set<Timer> _pendingDanmakuTimers = <Timer>{};
  Timer? _liveEventFlowTimer;
  Timer? _superChatRefreshTimer;
  Timer? _chatBottomRestoreTimer;
  Timer? _onlineRefreshTimer;
  Timer? _kuaishouContinuousBufferingTimer;
  Timer? _liveLatencyTelemetryTimer;
  final _liveLatencyTelemetryTracker = LiveLatencyTelemetryTracker();
  bool _onlineRefreshInFlight = false;
  bool _liveLatencyTelemetryInFlight = false;
  bool _hasActivePlaybackSession = false;
  bool _playbackBootstrapInFlight = false;
  int _kuaishouRecoverySessionRevision = 0;
  bool _autoQualityWarmupStartedForRoom = false;
  Future<void>? _kuaishouRecoveryFuture;

  /// 连续轮询失败（含 unknown/offline）次数，用于指数退避。
  int _onlineRefreshFailures = 0;
  DateTime? _ohosHealthyPlaybackSince;
  Duration _lastOhosPlaybackPosition = Duration.zero;

  /// 最近一次原生心跳到达的时间。
  ///
  /// 鸿蒙 AVPlayer 对部分直播源不暴露时间轴（currentTime 恒为 -1），此时
  /// position 永远不前进。心跳“有没有来”成为唯一可用的存活证据。
  DateTime? _ohosLastHeartbeatAt;
  bool _autoPipAttempting = false;

  @override
  void onInit() {
    CurrentRoomService.instance.setRoom(site, roomId);
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isWindows) {
      windowManager.addListener(this);
    }
    if (initialDesktopSidePanelCollapsed ||
        DesktopStartupArgs.startupCollapseChat) {
      desktopSidePanelCollapsed.value = true;
    }
    if (FollowService.instance.followList.isEmpty) {
      FollowService.instance.loadData(updateStatus: false);
    }
    initAutoExit();
    showDanmakuState.value = DesktopStartupArgs.isSecondaryDesktopInstance
        ? false
        : AppSettingsController.instance.danmuEnable.value;
    followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");
    loadData();
    _startLiveEventFlowTimer();

    scrollController.addListener(scrollListener);

    super.onInit();
    if (!Utils.isOhos) {
      _positionSubscription = player.stream.position.listen((event) {
        _lastKnownPlayerPosition = event;
      });
    }
    _setupAutoQualityAdjust();
  }

  // --- 播放中自动降画质（未锁定画质时，缓冲多次自动降一档） ---

  final LiveRoomAutoQualityBufferTracker _autoQualityBufferTracker =
      LiveRoomAutoQualityBufferTracker();

  /// 鸿蒙专用的降级证据门槛。
  ///
  /// 鸿蒙走这条更严格的判定，而不是 [_autoQualityBufferTracker] 的两次边沿：
  /// AVPlayer 在 HTTP-FLV 直播下会发出很短的 buffering 脉冲，按边沿计数会每隔
  /// 一两分钟就切一次线路，而每次切线路都会重建播放器、整屏转圈。
  final OhosPlaybackDegradeEvidence _ohosDegradeEvidence =
      OhosPlaybackDegradeEvidence();
  final KuaishouPlaybackRecoveryTracker _kuaishouPlaybackRecoveryTracker =
      KuaishouPlaybackRecoveryTracker();
  final OhosPlaybackSignalAdapter _ohosPlaybackSignalAdapter =
      OhosPlaybackSignalAdapter();

  /// 鸿蒙自动重连的确认配对器。
  ///
  /// 鸿蒙的重开只是同步请求 widget 重建，必须等原生播放确认才算重连完成，
  /// 否则恢复耗时只反映"请求发出"。见 [OhosReconnectConfirmation]。
  final OhosReconnectConfirmation _ohosReconnectConfirmation =
      OhosReconnectConfirmation();

  /// 待确认重连的超时兜底。原生确认到达即取消。
  Timer? _ohosReconnectConfirmationTimer;
  DateTime? _lastAutoQualityDownAt;
  final Set<int> _ohosFailedLineIndices = <int>{};
  StreamSubscription<bool>? _autoQualityBufferingSubscription;

  void _setupAutoQualityAdjust() {
    _autoQualityBufferingSubscription?.cancel();
    if (Utils.isOhos) {
      _autoQualityBufferingSubscription = null;
      return;
    }
    _autoQualityBufferingSubscription =
        player.stream.buffering.listen((buffering) {
      if (_roomDisposed) {
        return;
      }
      _observeKuaishouBuffering(buffering);
      _observeAutoQualityBuffering(buffering);
    });
  }

  void _observeAutoQualityBuffering(bool buffering) {
    if (_roomDisposed || _kuaishouPlaybackRecoveryTracker.recoveryInFlight) {
      return;
    }
    if (Utils.isOhos &&
        !AppSettingsController.instance.ohosAutoQualityDegrade.value) {
      return;
    }
    final now = DateTime.now();
    // 鸿蒙用证据门槛，其他平台保持原有的边沿计数不变。
    final bool shouldDegrade;
    if (Utils.isOhos) {
      shouldDegrade =
          _ohosDegradeEvidence.update(buffering: buffering, now: now);
      if (shouldDegrade) {
        // update 命中后会清空证据，所以这里读的是清空前记下的快照。
        Log.d('[ohos-degrade] 缓冲证据达标，准备切换线路/降画质');
      }
    } else {
      shouldDegrade =
          _autoQualityBufferTracker.update(buffering: buffering, now: now);
    }
    if (!shouldDegrade) {
      return;
    }
    if (_lastAutoQualityDownAt != null &&
        now.difference(_lastAutoQualityDownAt!) < const Duration(seconds: 30)) {
      return;
    }
    if (Utils.isOhos && playUrls.length > 1) {
      _ohosFailedLineIndices.add(currentLineIndex);
      final candidate = selectNextOhosFailoverLine(
        currentLineIndex: currentLineIndex,
        lineCount: playUrls.length,
        failedLineIndices: _ohosFailedLineIndices,
      );
      if (candidate != null) {
        _lastAutoQualityDownAt = now;
        SmartDialog.showToast("线路波动，已自动切换备用线路");
        unawaited(
          changePlayLine(
            candidate,
            persist: false,
            reconnectReason: LiveReconnectReason.automaticLineFailover,
          ),
        );
        return;
      }
    }
    if (qualityLocked.value ||
        currentQuality < 0 ||
        currentQuality >= qualites.length - 1) {
      return;
    }
    _lastAutoQualityDownAt = now;
    _ohosFailedLineIndices.clear();
    currentQuality += 1;
    currentQualityInfo.value = qualites[currentQuality].quality;
    SmartDialog.showToast("网络波动，已自动降低清晰度");
    unawaited(
      getPlayUrl(
        automaticReconnectReason: LiveReconnectReason.playbackUrlRefresh,
      ),
    );
  }

  @override
  bool get shouldDelegateStreamErrorsToRoomController =>
      site.id == Constant.kKuaishou;

  void _observeKuaishouBuffering(bool buffering) {
    if (site.id != Constant.kKuaishou || _roomDisposed) {
      return;
    }
    final now = DateTime.now();
    _kuaishouPlaybackRecoveryTracker.updateBuffering(
      buffering: buffering,
      now: now,
    );
    if (!buffering) {
      _kuaishouContinuousBufferingTimer?.cancel();
      _kuaishouContinuousBufferingTimer = null;
      return;
    }
    if (_kuaishouPlaybackRecoveryTracker.recoveryInFlight ||
        _kuaishouContinuousBufferingTimer != null) {
      return;
    }
    _kuaishouContinuousBufferingTimer = Timer(
      _kuaishouPlaybackRecoveryTracker.continuousRecoveryDelay(now),
      () {
        _kuaishouContinuousBufferingTimer = null;
        if (_roomDisposed || site.id != Constant.kKuaishou) {
          return;
        }
        if (_kuaishouPlaybackRecoveryTracker
            .triggerContinuousBufferingRecovery(DateTime.now())) {
          unawaited(_recoverKuaishouPlaybackAfterBuffering());
        }
      },
    );
  }

  void _resetKuaishouPlaybackRecoverySession() {
    _kuaishouRecoverySessionRevision += 1;
    _kuaishouRecoveryFuture = null;
    _kuaishouContinuousBufferingTimer?.cancel();
    _kuaishouContinuousBufferingTimer = null;
    _kuaishouPlaybackRecoveryTracker.reset();
  }

  void _resetOhosAutoLineSelectionSession() {
    _ohosPlayerLoadGeneration = null;
    _ohosPlayerRequestRevision = null;
    _ohosPlayerStartedDuringRecovery = false;
    _ohosAutoLineSelectionConsumed = false;
    _ohosAutoLineSwitchCompleted = false;
    _ohosAutoLineSelectionScheduledPlayerGeneration = null;
    ohosAutoLineSelectionDiagnostic.value = OhosAutoLineSelectionDiagnostic(
      status: OhosAutoLineSelectionStatus.idle,
      reason: 'room_session_started',
      roomGeneration: _loadGeneration,
      playbackRequestRevision: _playbackRequestRevision,
      playerGeneration: ohosPlayerRevision.value,
      manualLineSelectionRevision: _manualLineSelectionRevision,
      candidateCount: 0,
    );
  }

  void _updateOhosAutoLineSelectionDiagnostic({
    required OhosAutoLineSelectionStatus status,
    required String reason,
    int? roomGeneration,
    int? playbackRequestRevision,
    int? playerGeneration,
    int? manualLineSelectionRevision,
    int candidateCount = 0,
    int? initialLineIndex,
    int? selectedLineIndex,
    int? measuredLineIndex,
  }) {
    final diagnostic = OhosAutoLineSelectionDiagnostic(
      status: status,
      reason: reason,
      roomGeneration: roomGeneration ?? _loadGeneration,
      playbackRequestRevision:
          playbackRequestRevision ?? _playbackRequestRevision,
      playerGeneration: playerGeneration ?? ohosPlayerRevision.value,
      manualLineSelectionRevision:
          manualLineSelectionRevision ?? _manualLineSelectionRevision,
      candidateCount: candidateCount,
      initialLineIndex: initialLineIndex,
      selectedLineIndex: selectedLineIndex,
      measuredLineIndex: measuredLineIndex,
    );
    ohosAutoLineSelectionDiagnostic.value = diagnostic;
    Log.d(
      '[ohos-auto-line] status=${diagnostic.status.name} '
      'reason=${diagnostic.reason} '
      'roomGeneration=${diagnostic.roomGeneration} '
      'playbackRequestRevision=${diagnostic.playbackRequestRevision} '
      'playerGeneration=${diagnostic.playerGeneration} '
      'manualLineRevision=${diagnostic.manualLineSelectionRevision} '
      'candidateCount=${diagnostic.candidateCount} '
      'initialLine=${diagnostic.initialLineIndex ?? "none"} '
      'selectedLine=${diagnostic.selectedLineIndex ?? "none"} '
      'measuredLine=${diagnostic.measuredLineIndex ?? "none"}',
    );
  }

  void _resetPlaybackHealthSession() {
    if (!Utils.isOhos) {
      resetAutoNetworkDiagnosisSession();
    }
    _autoQualityBufferTracker.reset();
    _ohosDegradeEvidence.reset();
    _ohosReconnectConfirmationTimer?.cancel();
    _ohosReconnectConfirmationTimer = null;
    _ohosReconnectConfirmation.reset();
    _autoQualityWarmupStartedForRoom = false;
    _lastAutoQualityDownAt = null;
    _ohosFailedLineIndices.clear();
    _resetKuaishouPlaybackRecoverySession();
  }

  Future<void> _runKuaishouRecoverySingleFlight(
    Future<void> Function() operation,
  ) {
    final existing = _kuaishouRecoveryFuture;
    if (existing != null) {
      return existing;
    }
    late final Future<void> future;
    future = Future<void>.sync(operation).whenComplete(() {
      if (identical(_kuaishouRecoveryFuture, future)) {
        _kuaishouRecoveryFuture = null;
      }
    });
    _kuaishouRecoveryFuture = future;
    return future;
  }

  Future<void> _recoverKuaishouPlaybackAfterBuffering() async {
    final recoverySessionRevision = _kuaishouRecoverySessionRevision;
    try {
      await _runKuaishouRecoverySingleFlight(() async {
        if (recoverySessionRevision != _kuaishouRecoverySessionRevision) {
          return;
        }
        await setPlayer(
          refreshUrls: false,
          reconnectReason: LiveReconnectReason.sustainedBuffering,
        );
      });
    } catch (e, stackTrace) {
      Log.e('快手缓冲恢复失败: $e', stackTrace);
    } finally {
      if (recoverySessionRevision == _kuaishouRecoverySessionRevision) {
        _kuaishouPlaybackRecoveryTracker.finishRecovery();
        _kuaishouPlaybackRecoveryTracker.markPlaybackReopened();
      }
    }
  }

  void scrollListener() {
    if (!scrollController.hasClients) {
      return;
    }
    if (_isChatNearBottom()) {
      disableAutoScroll.value = false;
      return;
    }
    if (scrollController.position.userScrollDirection ==
        ScrollDirection.forward) {
      disableAutoScroll.value = true;
    }
  }

  bool _isChatNearBottom() {
    if (!scrollController.hasClients) {
      return true;
    }
    return scrollController.position.extentAfter <= 24;
  }

  bool _isKeywordShielded(LiveMessage msg) {
    final settings = AppSettingsController.instance;
    if (!settings.danmuShieldEnable.value ||
        !settings.danmuKeywordShieldEnable.value) {
      return false;
    }
    for (var keyword in settings.shieldList) {
      Pattern? pattern;
      if (Utils.isRegexFormat(keyword)) {
        String removedSlash = Utils.removeRegexFormat(keyword);
        try {
          pattern = RegExp(removedSlash);
        } catch (e) {
          Log.d("正则屏蔽词 $keyword 无法编译，已跳过");
        }
      } else {
        pattern = keyword;
      }
      if (pattern != null && msg.message.contains(pattern)) {
        Log.d("命中屏蔽词 $keyword\n已过滤消息: ${msg.message}");
        return true;
      }
    }
    return false;
  }

  bool _isDuplicateDanmu(LiveMessage msg) {
    if (msg.userName == "LiveSysMessage") {
      return false;
    }
    final settings = AppSettingsController.instance;
    if (!settings.danmuDedupeEnable.value) {
      return false;
    }
    final strictMode = settings.danmuDedupeStrictMode;
    final fingerprint = _buildDanmuFingerprint(
      msg,
      includeUserName: !strictMode,
    );
    if (fingerprint == null) {
      return false;
    }
    final windowSize = settings.effectiveDanmuDedupeWindow;
    final duplicate = _recentDanmuCounts.containsKey(fingerprint);
    _recentDanmuFingerprints.addLast(fingerprint);
    _recentDanmuCounts[fingerprint] =
        (_recentDanmuCounts[fingerprint] ?? 0) + 1;
    if (strictMode) {
      _recentDanmuEventsSincePrune = 0;
      _pruneRecentDanmuFingerprints(windowSize);
      return duplicate;
    }

    final step = settings.danmuDedupeStep.value.clamp(1, 20).toInt();
    _recentDanmuEventsSincePrune += 1;
    final shouldPrune = _recentDanmuEventsSincePrune >= step ||
        _recentDanmuFingerprints.length > windowSize + step - 1;
    if (shouldPrune) {
      _recentDanmuEventsSincePrune = 0;
    }
    if (shouldPrune) {
      _pruneRecentDanmuFingerprints(windowSize);
    }
    return duplicate;
  }

  void _pruneRecentDanmuFingerprints(int windowSize) {
    while (_recentDanmuFingerprints.length > windowSize) {
      final removed = _recentDanmuFingerprints.removeFirst();
      final count = (_recentDanmuCounts[removed] ?? 0) - 1;
      if (count <= 0) {
        _recentDanmuCounts.remove(removed);
      } else {
        _recentDanmuCounts[removed] = count;
      }
    }
  }

  String? _buildDanmuFingerprint(
    LiveMessage msg, {
    required bool includeUserName,
  }) {
    final parts = <String>[];
    final message = _normalizeDanmuFingerprintPart(msg.message);
    if (message.isNotEmpty) {
      parts.add("m:$message");
    }
    for (final span in msg.spans ?? const <LiveMessageSpan>[]) {
      final text = _normalizeDanmuFingerprintPart(span.text ?? "");
      final imageUrl = _normalizeDanmuFingerprintPart(span.imageUrl ?? "");
      if (text.isNotEmpty) {
        parts.add("t:$text");
      }
      if (imageUrl.isNotEmpty) {
        parts.add("i:$imageUrl");
      }
    }
    for (final imageUrl in msg.imageUrls ?? const <String>[]) {
      final value = _normalizeDanmuFingerprintPart(imageUrl);
      if (value.isNotEmpty) {
        parts.add("u:$value");
      }
    }
    if (parts.isEmpty) {
      return null;
    }
    if (!includeUserName) {
      return parts.join("\u0002");
    }
    final userName = _normalizeDanmuFingerprintPart(msg.userName);
    if (userName.isEmpty) {
      return null;
    }
    return "$userName\u0001${parts.join("\u0002")}";
  }

  String _normalizeDanmuFingerprintPart(String value) {
    return value.trim().replaceAll(RegExp(r"\s+"), " ");
  }

  void _clearDanmuDedupeState() {
    _recentDanmuFingerprints.clear();
    _recentDanmuCounts.clear();
    _recentDanmuEventsSincePrune = 0;
  }

  List<LiveSuperChatMessage> get sortedSuperChats {
    final list = superChats.toList();
    list.sort((a, b) => a.endTime.compareTo(b.endTime));
    if (AppSettingsController.instance.superChatSortDesc.value) {
      return list.reversed.toList();
    }
    return list;
  }

  bool _isUserShielded(String userName) {
    return AppSettingsController.instance.shouldShieldUser(
      userName,
      siteId: site.id,
    );
  }

  String _normalizeMessageText(String message) {
    return message.trim();
  }

  LiveRoomDetail _sanitizeRoomDetail(LiveRoomDetail detail) {
    return LiveRoomDetail(
      roomId: detail.roomId.trim(),
      title: detail.title.trim(),
      cover: detail.cover,
      userName: _normalizeUserName(detail.userName),
      userAvatar: detail.userAvatar,
      online: detail.online,
      introduction: detail.introduction?.trim(),
      notice: detail.notice?.trim(),
      status: detail.status,
      liveStatusState: detail.liveStatusState,
      data: detail.data,
      danmakuData: detail.danmakuData,
      url: detail.url,
      isRecord: detail.isRecord,
      showTime: detail.showTime?.trim(),
      categoryId: detail.categoryId?.trim(),
      categoryName: detail.categoryName?.trim(),
      categoryParentId: detail.categoryParentId?.trim(),
      categoryParentName: detail.categoryParentName?.trim(),
      categoryPic: detail.categoryPic?.trim(),
    );
  }

  void _syncBackgroundPlaybackMetadata(LiveRoomDetail roomDetail) {
    final title = roomDetail.title.isNotEmpty
        ? roomDetail.title
        : roomDetail.userName.isNotEmpty
            ? roomDetail.userName
            : site.name;
    unawaited(
      BackgroundPlaybackService.instance.updateMetadata(
        assetId: '${site.id}:${roomDetail.roomId}',
        siteId: site.id,
        roomId: roomDetail.roomId,
        title: title,
        artist: roomDetail.userName.isEmpty ? site.name : roomDetail.userName,
        album: site.name,
        artwork: roomDetail.cover,
      ),
    );
  }

  LiveMessage _sanitizeLiveMessage(LiveMessage message) {
    final normalizedUserName = message.userName == "LiveSysMessage"
        ? message.userName
        : _normalizeUserName(message.userName);
    final normalizedMessage = _normalizeMessageText(message.message);
    if (normalizedUserName == message.userName &&
        normalizedMessage == message.message) {
      return message;
    }

    return LiveMessage(
      type: message.type,
      userName: normalizedUserName,
      message: normalizedMessage,
      data: message.data,
      color: message.color,
      imageUrls: message.imageUrls,
      spans: message.spans,
    );
  }

  LiveMessage _superChatToLiveMessage(LiveSuperChatMessage superChat) {
    return LiveMessage(
      type: LiveMessageType.superChat,
      userName: superChat.userName,
      message: superChat.message,
      color: LiveMessageColor.white,
    );
  }

  String _normalizeUserName(String userName) {
    return userName.trim();
  }

  LiveSuperChatMessage _sanitizeSuperChatMessage(LiveSuperChatMessage message) {
    final normalizedUserName = _normalizeUserName(message.userName);
    final normalizedMessage = _normalizeMessageText(message.message);
    if (normalizedUserName == message.userName &&
        normalizedMessage == message.message) {
      return message;
    }

    return LiveSuperChatMessage(
      id: message.id,
      backgroundBottomColor: message.backgroundBottomColor,
      backgroundColor: message.backgroundColor,
      endTime: message.endTime,
      face: message.face,
      message: normalizedMessage,
      price: message.price,
      startTime: message.startTime,
      userName: normalizedUserName,
    );
  }

  LiveContributionRankItem _sanitizeContributionRankItem(
    LiveContributionRankItem item,
  ) {
    return LiveContributionRankItem(
      rank: item.rank,
      userName: _normalizeUserName(item.userName),
      avatar: item.avatar,
      scoreText: item.scoreText.trim(),
      scoreDetail: item.scoreDetail?.trim(),
      userLevel: item.userLevel,
      userLevelText: item.userLevelText?.trim(),
      userLevelIcon: item.userLevelIcon,
      fansLevel: item.fansLevel,
      fansName: item.fansName?.trim(),
      fansIcon: item.fansIcon,
    );
  }

  void toggleUserShield(String userName) {
    final value = _normalizeUserName(userName);
    if (value.isEmpty) {
      SmartDialog.showToast("用户名不能为空");
      return;
    }

    final settings = AppSettingsController.instance;
    if (settings.isUserShielded(value, siteId: site.id)) {
      settings.removeUserShieldList(value, siteId: site.id);
      SmartDialog.showToast("已取消屏蔽用户：$value");
      return;
    }

    settings.setDanmuShieldEnable(true);
    settings.setDanmuUserShieldEnable(true);
    settings.addUserShieldList(value, siteId: site.id);
    SmartDialog.showToast("已屏蔽用户：$value");
  }

  bool isTempMutedUser(String userName) {
    final value = _normalizeUserName(userName);
    if (value.isEmpty) {
      return false;
    }
    return tempMutedUsers.contains(value);
  }

  void toggleTempMuteUser(String userName) {
    final value = _normalizeUserName(userName);
    if (value.isEmpty) {
      SmartDialog.showToast("用户名不能为空");
      return;
    }
    if (tempMutedUsers.contains(value)) {
      tempMutedUsers.remove(value);
      tempMutedUsers.refresh();
      SmartDialog.showToast("已取消临时禁言：$value");
      return;
    }
    tempMutedUsers.add(value);
    tempMutedUsers.refresh();
    SmartDialog.showToast("已加入临时禁言：$value");
  }

  void clearTempMutedUsers() {
    if (tempMutedUsers.isEmpty) {
      SmartDialog.showToast("当前没有临时禁言用户");
      return;
    }
    tempMutedUsers.clear();
    tempMutedUsers.refresh();
    SmartDialog.showToast("已恢复全部临时禁言用户");
  }

  String? getUserRemark(String userName) {
    final value = _normalizeUserName(userName);
    if (value.isEmpty) {
      return null;
    }
    return AppSettingsController.instance.getUserRemark(
      value,
      siteId: site.id,
    );
  }

  Future<void> editUserRemark(String userName) async {
    final value = _normalizeUserName(userName);
    if (value.isEmpty) {
      SmartDialog.showToast("用户名不能为空");
      return;
    }
    final currentRemark = getUserRemark(value) ?? "";
    final result = await Utils.showEditTextDialog(
      currentRemark,
      title: "备注用户",
      hintText: "留空表示删除备注",
    );
    if (result == null) {
      return;
    }
    await AppSettingsController.instance.setUserRemark(
      siteId: site.id,
      userName: value,
      remark: result,
    );
    SmartDialog.showToast(
      result.trim().isEmpty ? "已删除备注" : "已更新备注：${result.trim()}",
    );
  }

  void showUserActions(
    String userName, {
    String? messageContent,
  }) {
    final value = _normalizeUserName(userName);
    if (value.isEmpty) {
      SmartDialog.showToast("用户名不能为空");
      return;
    }
    final normalizedMessage = messageContent == null
        ? null
        : _normalizeMessageText(messageContent).trim();
    final isShielded = AppSettingsController.instance.isUserShielded(
      value,
      siteId: site.id,
    );
    final isTempMuted = tempMutedUsers.contains(value);
    final remark = getUserRemark(value);

    Utils.showBottomSheet(
      title: value,
      child: ListView(
        shrinkWrap: true,
        children: [
          if (remark != null && remark.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text("当前备注：$remark"),
              dense: true,
            ),
          ListTile(
            leading: Icon(
              isShielded ? Icons.visibility_outlined : Icons.block_outlined,
            ),
            title: Text(isShielded ? "取消平台屏蔽" : "屏蔽当前平台"),
            subtitle: Text("仅对 ${site.name} 生效，不会误伤其他平台同名用户"),
            onTap: () {
              Get.back();
              toggleUserShield(value);
            },
          ),
          ListTile(
            leading: Icon(
              isTempMuted
                  ? Icons.volume_up_outlined
                  : Icons.volume_off_outlined,
            ),
            title: Text(isTempMuted ? "取消临时禁言" : "加入临时禁言"),
            subtitle: const Text("只在当前直播间本次会话内有效"),
            onTap: () {
              Get.back();
              toggleTempMuteUser(value);
            },
          ),
          ListTile(
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: const Text("快捷备注"),
            onTap: () async {
              Get.back();
              await editUserRemark(value);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text("复制用户名"),
            onTap: () {
              Get.back();
              copyUserName(value);
            },
          ),
          if (normalizedMessage != null && normalizedMessage.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text("复制弹幕内容"),
              subtitle: Text(
                normalizedMessage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                Get.back();
                copyMessageContent(normalizedMessage);
              },
            ),
          ListTile(
            leading: const Icon(Icons.restore_outlined),
            title: const Text("批量恢复临时禁言"),
            enabled: tempMutedUsers.isNotEmpty,
            onTap: tempMutedUsers.isEmpty
                ? null
                : () {
                    Get.back();
                    clearTempMutedUsers();
                  },
          ),
        ],
      ),
    );
  }

  void copyUserName(String userName) {
    final value = _normalizeUserName(userName);
    if (value.isEmpty) {
      SmartDialog.showToast("用户名不能为空");
      return;
    }
    Utils.copyToClipboard(value);
    SmartDialog.showToast("已复制用户名：$value");
  }

  void copyMessageContent(String message) {
    final value = _normalizeMessageText(message).trim();
    if (value.isEmpty) {
      SmartDialog.showToast("弹幕内容为空");
      return;
    }
    Utils.copyToClipboard(value);
    SmartDialog.showToast("已复制弹幕内容");
  }

  void updateDanmakuViewportHeight(double value) {
    if (value <= 0) {
      return;
    }
    if ((danmakuViewportHeight.value - value).abs() < 0.5) {
      return;
    }
    danmakuViewportHeight.value = value;
  }

  void _cancelPendingDanmakuTimers() {
    for (final timer in _pendingDanmakuTimers.toList()) {
      timer.cancel();
    }
    _pendingDanmakuTimers.clear();
  }

  void _scheduleOverlayDanmaku(LiveMessage msg) {
    final color = Color.fromARGB(
      255,
      msg.color.r,
      msg.color.g,
      msg.color.b,
    );
    final baseDelayMs = AppSettingsController.instance.getDanmuDelayMs(site.id);
    final totalDelayMs = baseDelayMs + (site.id == Constant.kHuya ? 1000 : 0);
    final delay = Duration(milliseconds: totalDelayMs.clamp(0, 6000));
    final renderEmoji = AppSettingsController.instance.danmuRenderEmoji.value;
    final parts = renderEmoji ? _buildDanmakuContentParts(msg.spans) : null;
    rememberDanmakuReplay(
      msg.message,
      color,
      delay: delay,
      imageUrls: renderEmoji && parts == null ? msg.imageUrls : null,
      parts: parts,
    );

    void emit() {
      if (!showDanmakuState.value ||
          !liveStatus.value ||
          (isBackground && !_allowBackgroundPlayback)) {
        return;
      }
      addDanmaku([
        DanmakuContentItem(
          msg.message,
          color: color,
          imageUrls: renderEmoji && parts == null ? msg.imageUrls : null,
          parts: parts,
        ),
      ]);
    }

    if (delay == Duration.zero) {
      emit();
      return;
    }

    Timer? timer;
    timer = Timer(delay, () {
      if (timer != null) {
        _pendingDanmakuTimers.remove(timer);
      }
      emit();
    });
    _pendingDanmakuTimers.add(timer);
  }

  List<DanmakuContentPart>? _buildDanmakuContentParts(
    List<LiveMessageSpan>? spans,
  ) {
    final source = spans ?? const <LiveMessageSpan>[];
    if (source.isEmpty) {
      return null;
    }
    final parts = <DanmakuContentPart>[];
    for (final span in source) {
      if (span.isText) {
        final text = span.text ?? "";
        if (text.isNotEmpty) {
          parts.add(DanmakuContentPart.text(text));
        }
      } else if (span.isImage) {
        final imageUrl = (span.imageUrl ?? "").trim();
        if (imageUrl.isNotEmpty) {
          parts.add(
            DanmakuContentPart.image(
              imageUrl,
              fallbackText: span.fallbackText,
            ),
          );
        }
      }
    }
    return parts.isEmpty ? null : parts;
  }

  String _buildSuperChatFingerprint(LiveSuperChatMessage message) {
    final id = message.id?.trim();
    if (id != null && id.isNotEmpty) {
      return "id:$id";
    }

    return [
      message.userName,
      message.message,
      message.price,
      message.startTime.millisecondsSinceEpoch,
      message.endTime.millisecondsSinceEpoch,
    ].join("|");
  }

  bool _shouldUpdateSuperChat(
    LiveSuperChatMessage current,
    LiveSuperChatMessage next,
  ) {
    if ((current.endTime.difference(next.endTime).inSeconds).abs() > 1) {
      return true;
    }

    return current.startTime != next.startTime ||
        current.face != next.face ||
        current.message != next.message ||
        current.price != next.price ||
        current.userName != next.userName ||
        current.backgroundColor != next.backgroundColor ||
        current.backgroundBottomColor != next.backgroundBottomColor;
  }

  void _appendSuperChats(Iterable<LiveSuperChatMessage> items) {
    final now = DateTime.now();
    final added = <LiveSuperChatMessage>[];
    for (final item in items) {
      if (!item.endTime.isAfter(now)) {
        continue;
      }
      final fingerprint = _buildSuperChatFingerprint(item);
      final existingIndex = superChats.indexWhere(
        (existing) => _buildSuperChatFingerprint(existing) == fingerprint,
      );
      if (existingIndex >= 0) {
        if (_shouldUpdateSuperChat(superChats[existingIndex], item)) {
          superChats[existingIndex] = item;
        }
        continue;
      }
      if (_superChatFingerprints.add(fingerprint)) {
        added.add(item);
      }
    }
    if (added.isNotEmpty) {
      superChats.addAll(added);
    }
    _sortSuperChats();
  }

  void _sortSuperChats() {
    superChats.sort((a, b) => a.endTime.compareTo(b.endTime));
  }

  void _refreshSuperChatFingerprints() {
    _superChatFingerprints
      ..clear()
      ..addAll(superChats.map(_buildSuperChatFingerprint));
  }

  void _restartSuperChatRefreshTimer() {
    _superChatRefreshTimer?.cancel();
    if (site.id != Constant.kHuya || !liveStatus.value) {
      return;
    }
    _superChatRefreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      removeSuperChats();
      getSuperChatMessage(silent: true);
    });
  }

  void _clearSuperChatState() {
    superChats.clear();
    _superChatFingerprints.clear();
    _superChatRefreshTimer?.cancel();
    _superChatRefreshTimer = null;
  }

  bool get showOfflineOverlay =>
      roomLiveState.value == LiveStatusState.offline &&
      offlineConfirmations.value >= 3 &&
      !_hasActivePlaybackSession &&
      !_hasActivePlaybackForRoomStatus;

  /// 读取房间详情。快手请求通过 [KuaishouRequestTrace] 标记来源，
  /// 供 core 侧按来源汇总请求量；其他平台不带来源标记。
  Future<LiveRoomDetail> _fetchRoomDetailWithSource({
    KuaishouRequestSource? source,
  }) {
    if (source == null) {
      return site.liveSite.getRoomDetail(roomId: roomId);
    }
    return KuaishouRequestTrace.run(
      source,
      () => site.liveSite.getRoomDetail(roomId: roomId),
    );
  }

  void _restartOnlineRefreshTimer() {
    _onlineRefreshTimer?.cancel();
    _onlineRefreshTimer = null;
    if (_roomDisposed) {
      return;
    }

    // 快手稳定播放时保留分钟级低频复核，避免完整停轮询后无法发现
    // 失效的播放会话；非稳定路径仍使用原有状态退避。
    if (site.id == Constant.kKuaishou && _isStablyPlaying()) {
      final delay = resolveKuaishouStableRefreshDelay(
        jitterSeconds: Random().nextInt(61) - 30,
      );
      Log.d("[ks-poll] schedule stable recheck after ${delay.inSeconds}s "
          "state=${roomLiveState.value.name}");
      _onlineRefreshTimer = Timer(delay, _refreshRoomStatus);
      return;
    }

    final delay = showOfflineOverlay
        ? const Duration(seconds: 45)
        : _resolveOnlineRefreshDelay();
    _onlineRefreshTimer = Timer(delay, _refreshRoomStatus);
  }

  /// 是否正在稳定播放（作为快手轮询主信号）。
  bool _isStablyPlaying() {
    if (Utils.isOhos) {
      final value = ohosVideoController?.value;
      return value != null &&
          isLiveRoomPlaybackStable(
            initialized: value.isInitialized,
            playing: value.isPlaying,
            buffering: value.isBuffering,
            hasError: value.hasError,
          );
    }
    return isLiveRoomPlaybackStable(
      initialized: _hasActivePlaybackSession,
      playing: player.state.playing,
      buffering: player.state.buffering,
      hasError: false,
    );
  }

  /// 根据当前状态决定下次轮询间隔：unknown/失败走指数退避。
  ///
  /// 连续失败次数由 [_onlineRefreshFailures] 记录；失败时按
  /// 10s → 30s → 60s → 120s → 240s 指数增长，封顶 300s；
  /// 恢复到 live 后重置为 10s。
  Duration _resolveOnlineRefreshDelay() {
    return resolveOnlineRefreshDelay(
      roomLiveState.value,
      _onlineRefreshFailures,
    );
  }

  Future<void> _refreshRoomStatus() async {
    if (_onlineRefreshInFlight || _roomDisposed) {
      _restartOnlineRefreshTimer();
      return;
    }
    _onlineRefreshInFlight = true;
    final refreshGeneration = _loadGeneration;
    try {
      final roomDetail = _sanitizeRoomDetail(
        await _fetchRoomDetailWithSource(
          source: site.id == Constant.kKuaishou
              ? KuaishouRequestSource.roomStatusPolling
              : null,
        ).timeout(const Duration(seconds: 8)),
      );
      if (!_isCurrentLoad(refreshGeneration)) {
        return;
      }
      final incomingState = roomDetail.resolvedLiveStatus;
      final decision = _applyRoomLiveState(incomingState);
      if (shouldCommitRoomDetailRefresh(
        incomingState: incomingState,
        decision: decision,
      )) {
        final currentDetail = detail.value;
        final committedDetail =
            site.id == Constant.kKuaishou && currentDetail != null
                ? mergeKuaishouRoomDetailMetadata(
                    current: currentDetail,
                    incoming: roomDetail,
                  )
                : roomDetail;
        detail.value = committedDetail;
        online.value = committedDetail.online;
        _syncBackgroundPlaybackMetadata(committedDetail);
      }
      if (incomingState == LiveStatusState.live) {
        await _bootstrapPlaybackIfNeeded();
      }
    } catch (e) {
      Log.d("刷新${site.name}直播状态失败，保留当前状态: $e");
      if (!_isCurrentLoad(refreshGeneration)) {
        return;
      }
      _applyRoomLiveState(LiveStatusState.unknown);
    } finally {
      _onlineRefreshInFlight = false;
      if (_isCurrentLoad(refreshGeneration)) {
        _restartOnlineRefreshTimer();
      }
    }
  }

  RoomLiveRefreshDecision _applyRoomLiveState(
    LiveStatusState incomingState,
  ) {
    _onlineRefreshFailures = resolveOnlineRefreshFailureCount(
      incomingState: incomingState,
      currentFailures: _onlineRefreshFailures,
    );
    final decision = resolveRoomLiveRefresh(
      currentState: roomLiveState.value,
      incomingState: incomingState,
      consecutiveOfflineReports: offlineConfirmations.value,
      currentLiveStatus: liveStatus.value,
      playbackActive:
          _hasActivePlaybackSession || _hasActivePlaybackForRoomStatus,
    );
    roomLiveState.value = decision.state;
    offlineConfirmations.value = decision.consecutiveOfflineReports;
    final statusChanged = liveStatus.value != decision.liveStatus;
    liveStatus.value = decision.liveStatus;
    if (incomingState == LiveStatusState.live) {
      loadError.value = false;
      error = null;
      errorStackTrace = null;
    } else if (decision.state == LiveStatusState.offline) {
      waitingForPlaybackUrl.value = false;
    }
    if (statusChanged) {
      _restartSuperChatRefreshTimer();
    }
    return decision;
  }

  Future<void> _bootstrapPlaybackIfNeeded() async {
    if (_roomDisposed ||
        _playbackBootstrapInFlight ||
        roomLiveState.value != LiveStatusState.live ||
        _hasActivePlaybackSession) {
      return;
    }
    _playbackBootstrapInFlight = true;
    waitingForPlaybackUrl.value = true;
    try {
      await getPlayQualites();
    } finally {
      _playbackBootstrapInFlight = false;
    }
  }

  bool get _hasActivePlaybackForRoomStatus {
    if (Utils.isOhos) {
      final value = ohosVideoController?.value;
      return value != null &&
          value.isInitialized &&
          !value.hasError &&
          (value.isPlaying || value.isBuffering);
    }
    return player.state.playing;
  }

  @override
  void updateOhosVideoState(VideoPlayerValue value) {
    super.updateOhosVideoState(value);
    if (!Utils.isOhos) {
      return;
    }
    _observeKuaishouBuffering(
      value.isInitialized && !value.hasError && value.isBuffering,
    );
    if (!value.isInitialized ||
        value.hasError ||
        value.isBuffering ||
        !value.isPlaying) {
      _ohosHealthyPlaybackSince = null;
      _lastOhosPlaybackPosition = value.position;
      return;
    }
    final now = DateTime.now();
    final positionProgressed = didOhosPlaybackTimelineProgress(
      current: value.position,
      previous: _lastOhosPlaybackPosition,
    );
    if (positionProgressed) {
      _lastOhosPlaybackPosition = value.position;
    } else if (!_ohosHeartbeatLooksAlive(now)) {
      // 时间轴不前进、心跳也没来：不能认定为健康播放。
      return;
    }
    _ohosHealthyPlaybackSince ??= now;
    if (mediaErrorRetryCount > 0 &&
        now.difference(_ohosHealthyPlaybackSince!) >=
            const Duration(seconds: 20)) {
      Log.d("鸿蒙播放器已稳定播放，重置错误重试计数");
      mediaErrorRetryCount = 0;
    }
  }

  /// 原生心跳是否表明播放器仍在推进。
  ///
  /// 心跳约每秒一次，这里给足容忍窗口，避免一次调度抖动就被判成不活。
  bool _ohosHeartbeatLooksAlive(DateTime now) {
    final lastHeartbeatAt = _ohosLastHeartbeatAt;
    return lastHeartbeatAt != null &&
        now.difference(lastHeartbeatAt) < ohosHeartbeatStallTimeout;
  }

  /// 挂起一次鸿蒙自动重连，等原生播放确认后再写入健康事件。
  ///
  /// 与 mpv 侧的差别：mpv 的 `player.open()` resolve 时链路已经建立，
  /// 所以那边在重开返回处直接记账；鸿蒙的重开返回只代表请求已发出。
  ///
  /// 调用时机要求：必须在 `initPlaylist` 推进 [ohosPlayerRevision] 之后、
  /// 且在下一帧 widget 重建之前调用（当前两者之间没有 await，成立）。
  /// 万一将来插入 await 使 initialized 先到，心跳与 15s 超时仍会兜住这次重连，
  /// 只是恢复耗时会偏长——次数不会丢。
  void _armOhosReconnect({
    required LiveReconnectReason reason,
    required bool? hostChanged,
    required DateTime? startedAt,
  }) {
    final now = DateTime.now();
    final displaced = _ohosReconnectConfirmation.arm(
      reason: reason,
      hostChanged: hostChanged,
      startedAt: startedAt,
      now: now,
      playerGeneration: ohosPlayerRevision.value,
    );
    if (displaced != null) {
      _recordOhosReconnectOutcome(displaced);
    }
    _ohosReconnectConfirmationTimer?.cancel();
    _ohosReconnectConfirmationTimer = Timer(
      _ohosReconnectConfirmation.confirmationTimeout,
      () {
        if (_roomDisposed) {
          return;
        }
        final expired = _ohosReconnectConfirmation.flushIfExpired(
          DateTime.now(),
        );
        if (expired != null) {
          _recordOhosReconnectOutcome(expired);
        }
      },
    );
  }

  /// 原生播放确认到达（initialized / 首帧 / 心跳任一），定稿待确认重连。
  void _confirmOhosReconnect(int playerGeneration) {
    if (_ohosReconnectConfirmation.pending == null) {
      return;
    }
    final outcome = _ohosReconnectConfirmation.confirm(
      playerGeneration: playerGeneration,
      now: DateTime.now(),
    );
    if (outcome == null) {
      return;
    }
    _ohosReconnectConfirmationTimer?.cancel();
    _ohosReconnectConfirmationTimer = null;
    _recordOhosReconnectOutcome(outcome);
  }

  void _recordOhosReconnectOutcome(OhosReconnectOutcome outcome) {
    Log.d(
      '鸿蒙自动重连记账 reason=${outcome.reason.name} '
      'confirmed=${outcome.confirmed} '
      'hostChanged=${outcome.hostChanged} '
      'recovery=${outcome.recoveryDuration?.inMilliseconds ?? "unknown"}ms '
      'playerGeneration=${outcome.playerGeneration}',
    );
    recordLiveLinkHealthEvent(
      LiveLinkEventType.cdnReconnect,
      at: outcome.occurredAt,
      reconnectReason: outcome.reason,
      reconnectHostChanged: outcome.hostChanged,
      reconnectRecoveryDuration: outcome.recoveryDuration,
    );
  }

  /// 接收鸿蒙播放器的原生遥测（心跳与缓存深度）。
  void updateOhosTelemetryForGeneration(
    int playerGeneration,
    OhosPlaybackTelemetry telemetry,
  ) {
    if (!Utils.isOhos ||
        _roomDisposed ||
        playerGeneration != ohosPlayerRevision.value) {
      return;
    }
    // 只有原生时钟跳动算心跳。缓存事件不带 heartbeatAt，避免"缓冲还在报深度"
    // 被当成"播放器还活着"。
    final heartbeatAt = telemetry.heartbeatAt;
    if (heartbeatAt != null) {
      _ohosLastHeartbeatAt = heartbeatAt;
      recordOhosNativeHeartbeat(heartbeatAt);
      // 兜底确认路径：有些直播源 currentTime 恒为 -1，首帧/进度可能都不来，
      // 心跳是唯一能证明这代播放器真的活了的信号。
      _confirmOhosReconnect(playerGeneration);
    }
    if (telemetry.cacheDuration != null) {
      recordOhosDemuxerCacheDuration(telemetry.cacheDuration);
    }
  }

  void updateOhosVideoStateForGeneration(
    int playerGeneration,
    VideoPlayerValue value,
  ) {
    if (!Utils.isOhos ||
        _roomDisposed ||
        playerGeneration != ohosPlayerRevision.value) {
      return;
    }
    final signals = _ohosPlaybackSignalAdapter.update(
      roomGeneration: _loadGeneration,
      playerGeneration: playerGeneration,
      value: value,
    );
    if (signals.isEmpty) {
      return;
    }
    for (final signal in signals) {
      switch (signal.type) {
        case OhosPlaybackSignalType.bufferingStarted:
          recordLiveLinkHealthEvent(
            LiveLinkEventType.bufferingStarted,
            at: signal.occurredAt,
          );
          break;
        case OhosPlaybackSignalType.bufferingEnded:
          recordLiveLinkHealthEvent(
            LiveLinkEventType.bufferingEnded,
            at: signal.occurredAt,
          );
          break;
        case OhosPlaybackSignalType.firstFrame:
        case OhosPlaybackSignalType.initialized:
          _logOhosPlaybackSignal(signal);
          // AVPlayer 已接受地址并报出尺寸/时长，或已经出画：
          // 这才是"重开真的成功了"，可以给待确认重连定稿。
          _confirmOhosReconnect(signal.playerGeneration);
          break;
        case OhosPlaybackSignalType.nativeError:
        case OhosPlaybackSignalType.sourceReopened:
          _logOhosPlaybackSignal(signal);
          break;
        case OhosPlaybackSignalType.playing:
        case OhosPlaybackSignalType.positionAdvanced:
        case OhosPlaybackSignalType.mediaHttpError:
        case OhosPlaybackSignalType.sourceAssigned:
        case OhosPlaybackSignalType.disposed:
          break;
      }
    }
    _observeAutoQualityBuffering(
      value.isInitialized && !value.hasError && value.isBuffering,
    );
    observeAutoNetworkDiagnosisBuffering(
      value.isInitialized && !value.hasError && value.isBuffering,
    );
    updateOhosVideoState(value);
  }

  void _logOhosPlaybackSignal(OhosPlaybackSignal signal) {
    Log.d(
      'OHOS playback signal=${signal.type.name} '
      'roomGeneration=${signal.roomGeneration} '
      'playerGeneration=${signal.playerGeneration} '
      'source=${signal.sourceFingerprint} '
      'error=${signal.nativeErrorCode ?? "none"}',
    );
  }

  void updateOhosFirstFrameForGeneration(int playerGeneration) {
    if (!Utils.isOhos ||
        _roomDisposed ||
        playerGeneration != ohosPlayerRevision.value) {
      return;
    }
    // 首帧是最强的播放确认，即使 markFirstFrame 已去重也要走确认。
    _confirmOhosReconnect(playerGeneration);
    final signal = _ohosPlaybackSignalAdapter.markFirstFrame(
      roomGeneration: _loadGeneration,
      playerGeneration: playerGeneration,
    );
    if (signal == null) {
      // The value callback may already have de-duplicated the signal.  This
      // method is still the real native first-frame callback and is therefore
      // the only place where post-first-frame line selection is scheduled.
    } else {
      _logOhosPlaybackSignal(signal);
    }
    _scheduleOhosAutoSelectFastestLineAfterFirstFrame(playerGeneration);
  }

  bool get _ohosPlayerRecoveryInFlight {
    return _roomSwitching ||
        _playerReopenCompleter != null ||
        _ohosPlayerStartedDuringRecovery ||
        _ohosReconnectConfirmation.pending != null;
  }

  void _scheduleOhosAutoSelectFastestLineAfterFirstFrame(
    int playerGeneration,
  ) {
    final loadGeneration = _ohosPlayerLoadGeneration;
    final requestRevision = _ohosPlayerRequestRevision;
    if (loadGeneration == null || requestRevision == null) {
      _updateOhosAutoLineSelectionDiagnostic(
        status: OhosAutoLineSelectionStatus.skipped,
        reason: 'missing_player_snapshot',
        playerGeneration: playerGeneration,
      );
      return;
    }
    if (_ohosAutoLineSelectionScheduledPlayerGeneration == playerGeneration) {
      return;
    }
    // Native callbacks may be delivered more than once.  Reserve this player
    // generation before any await so duplicate first-frame callbacks cannot
    // start another probe.
    _ohosAutoLineSelectionScheduledPlayerGeneration = playerGeneration;

    final manualLineSelectionRevision = _manualLineSelectionRevision;
    final candidateIndices = resolveOhosAutoLineCandidateIndices(
      urls: playUrls,
      currentLineIndex: currentLineIndex,
    );
    final initialLineIndex = currentLineIndex;
    if (!AppSettingsController.instance.autoSelectFastestLine.value) {
      _updateOhosAutoLineSelectionDiagnostic(
        status: OhosAutoLineSelectionStatus.skipped,
        reason: 'setting_disabled',
        roomGeneration: loadGeneration,
        playbackRequestRevision: requestRevision,
        playerGeneration: playerGeneration,
        manualLineSelectionRevision: manualLineSelectionRevision,
        candidateCount: candidateIndices.length,
        initialLineIndex: initialLineIndex,
      );
      return;
    }
    if (!_ohosCurrentPlayerSnapshotIsCurrent(
      loadGeneration: loadGeneration,
      requestRevision: requestRevision,
      playerGeneration: playerGeneration,
    )) {
      _updateOhosAutoLineSelectionDiagnostic(
        status: OhosAutoLineSelectionStatus.stale,
        reason: 'snapshot_changed_before_measurement',
        roomGeneration: loadGeneration,
        playbackRequestRevision: requestRevision,
        playerGeneration: playerGeneration,
        manualLineSelectionRevision: manualLineSelectionRevision,
        candidateCount: candidateIndices.length,
        initialLineIndex: initialLineIndex,
      );
      return;
    }
    if (!_ohosPlayerAutoLineSelectionAllowed) {
      _updateOhosAutoLineSelectionDiagnostic(
        status: OhosAutoLineSelectionStatus.skipped,
        reason: 'user_playback_operation',
        roomGeneration: loadGeneration,
        playbackRequestRevision: requestRevision,
        playerGeneration: playerGeneration,
        manualLineSelectionRevision: manualLineSelectionRevision,
        candidateCount: candidateIndices.length,
        initialLineIndex: initialLineIndex,
      );
      return;
    }
    if (_ohosPlayerStartedDuringRecovery || _ohosPlayerRecoveryInFlight) {
      _updateOhosAutoLineSelectionDiagnostic(
        status: OhosAutoLineSelectionStatus.skipped,
        reason: 'player_recovery_in_flight',
        roomGeneration: loadGeneration,
        playbackRequestRevision: requestRevision,
        playerGeneration: playerGeneration,
        manualLineSelectionRevision: manualLineSelectionRevision,
        candidateCount: candidateIndices.length,
        initialLineIndex: initialLineIndex,
      );
      return;
    }
    if (_ohosAutoLineSelectionConsumed) {
      _updateOhosAutoLineSelectionDiagnostic(
        status: OhosAutoLineSelectionStatus.skipped,
        reason: 'session_already_evaluated',
        roomGeneration: loadGeneration,
        playbackRequestRevision: requestRevision,
        playerGeneration: playerGeneration,
        manualLineSelectionRevision: manualLineSelectionRevision,
        candidateCount: candidateIndices.length,
        initialLineIndex: initialLineIndex,
      );
      return;
    }
    if (candidateIndices.length <= 1) {
      _updateOhosAutoLineSelectionDiagnostic(
        status: OhosAutoLineSelectionStatus.skipped,
        reason: 'single_protocol_tier_line',
        roomGeneration: loadGeneration,
        playbackRequestRevision: requestRevision,
        playerGeneration: playerGeneration,
        manualLineSelectionRevision: manualLineSelectionRevision,
        candidateCount: candidateIndices.length,
        initialLineIndex: initialLineIndex,
      );
      return;
    }

    final candidates = [
      for (final index in candidateIndices) playUrls[index],
    ];
    // One room playback session gets one background decision.  Mark the
    // decision consumed before yielding to the network so a later recovery
    // cannot launch a second probe or switch twice.
    _ohosAutoLineSelectionConsumed = true;
    _updateOhosAutoLineSelectionDiagnostic(
      status: OhosAutoLineSelectionStatus.measuring,
      reason: 'first_frame_received',
      roomGeneration: loadGeneration,
      playbackRequestRevision: requestRevision,
      playerGeneration: playerGeneration,
      manualLineSelectionRevision: manualLineSelectionRevision,
      candidateCount: candidates.length,
      initialLineIndex: initialLineIndex,
    );
    unawaited(
      _selectFastestOhosLineAfterFirstFrame(
        roomGeneration: loadGeneration,
        playbackRequestRevision: requestRevision,
        playerGeneration: playerGeneration,
        manualLineSelectionRevision: manualLineSelectionRevision,
        initialLineIndex: initialLineIndex,
        candidateIndices: candidateIndices,
        candidates: candidates,
      ),
    );
  }

  bool _ohosCurrentPlayerSnapshotIsCurrent({
    required int loadGeneration,
    required int requestRevision,
    required int playerGeneration,
  }) {
    return !_roomDisposed &&
        playerGeneration == ohosPlayerRevision.value &&
        loadGeneration == _loadGeneration &&
        requestRevision == _playbackRequestRevision;
  }

  bool get _ohosPlayerAutoLineSelectionAllowed =>
      _ohosPlayerStartedDuringRecovery == false &&
      _ohosCurrentPlayerAllowsAutoLineSelection;

  bool _ohosCurrentPlayerAllowsAutoLineSelection = true;

  Future<void> _selectFastestOhosLineAfterFirstFrame({
    required int roomGeneration,
    required int playbackRequestRevision,
    required int playerGeneration,
    required int manualLineSelectionRevision,
    required int initialLineIndex,
    required List<int> candidateIndices,
    required List<String> candidates,
  }) async {
    int fastest;
    try {
      fastest = await NetworkDiagnoseService.findFastestLine(candidates);
    } catch (e) {
      _updateOhosAutoLineSelectionDiagnostic(
        status: OhosAutoLineSelectionStatus.failed,
        reason: 'measurement_error_${e.runtimeType}',
        roomGeneration: roomGeneration,
        playbackRequestRevision: playbackRequestRevision,
        playerGeneration: playerGeneration,
        manualLineSelectionRevision: manualLineSelectionRevision,
        candidateCount: candidates.length,
        initialLineIndex: initialLineIndex,
      );
      // Do not include exception text: network errors may contain a source
      // URL on some platform implementations.
      Log.d(
        '[ohos-auto-line] measurement failed '
        'errorType=${e.runtimeType} roomGeneration=$roomGeneration '
        'playbackRequestRevision=$playbackRequestRevision '
        'playerGeneration=$playerGeneration',
      );
      return;
    }

    final candidateIndex = fastest.clamp(0, candidates.length - 1).toInt();

    final isCurrent = shouldAcceptOhosAutoLineSelection(
      roomGeneration: roomGeneration,
      expectedRoomGeneration: _loadGeneration,
      playbackRequestRevision: playbackRequestRevision,
      latestPlaybackRequestRevision: _playbackRequestRevision,
      playerGeneration: playerGeneration,
      currentPlayerGeneration: ohosPlayerRevision.value,
      manualLineSelectionRevision: manualLineSelectionRevision,
      latestManualLineSelectionRevision: _manualLineSelectionRevision,
      hasActivePlaybackSession: _hasActivePlaybackSession,
      playerRecovering: _ohosPlayerRecoveryInFlight,
      autoLineSwitchAlreadyCompleted: _ohosAutoLineSwitchCompleted,
    );
    if (!isCurrent) {
      _updateOhosAutoLineSelectionDiagnostic(
        status: OhosAutoLineSelectionStatus.stale,
        reason: 'snapshot_changed_after_measurement',
        roomGeneration: roomGeneration,
        playbackRequestRevision: playbackRequestRevision,
        playerGeneration: playerGeneration,
        manualLineSelectionRevision: manualLineSelectionRevision,
        candidateCount: candidates.length,
        initialLineIndex: initialLineIndex,
        measuredLineIndex: candidateIndex,
      );
      return;
    }

    final selectedLineIndex = candidateIndices[candidateIndex];
    if (selectedLineIndex == currentLineIndex) {
      _updateOhosAutoLineSelectionDiagnostic(
        status: OhosAutoLineSelectionStatus.skipped,
        reason: 'current_line_is_fastest',
        roomGeneration: roomGeneration,
        playbackRequestRevision: playbackRequestRevision,
        playerGeneration: playerGeneration,
        manualLineSelectionRevision: manualLineSelectionRevision,
        candidateCount: candidates.length,
        initialLineIndex: initialLineIndex,
        selectedLineIndex: selectedLineIndex,
        measuredLineIndex: candidateIndex,
      );
      return;
    }

    // Re-check the active index immediately before changing it.  This closes
    // the small synchronous gap between the acceptance guard and the call into
    // the playback state machine.
    if (currentLineIndex != initialLineIndex ||
        !_ohosCurrentPlayerSnapshotIsCurrent(
          loadGeneration: roomGeneration,
          requestRevision: playbackRequestRevision,
          playerGeneration: playerGeneration,
        ) ||
        _ohosPlayerRecoveryInFlight ||
        _manualLineSelectionRevision != manualLineSelectionRevision) {
      _updateOhosAutoLineSelectionDiagnostic(
        status: OhosAutoLineSelectionStatus.stale,
        reason: 'selection_changed_before_switch',
        roomGeneration: roomGeneration,
        playbackRequestRevision: playbackRequestRevision,
        playerGeneration: playerGeneration,
        manualLineSelectionRevision: manualLineSelectionRevision,
        candidateCount: candidates.length,
        initialLineIndex: initialLineIndex,
        selectedLineIndex: selectedLineIndex,
        measuredLineIndex: candidateIndex,
      );
      return;
    }

    _ohosAutoLineSwitchCompleted = true;
    _updateOhosAutoLineSelectionDiagnostic(
      status: OhosAutoLineSelectionStatus.switched,
      reason: 'fastest_line_selected',
      roomGeneration: roomGeneration,
      playbackRequestRevision: playbackRequestRevision,
      playerGeneration: playerGeneration,
      manualLineSelectionRevision: manualLineSelectionRevision,
      candidateCount: candidates.length,
      initialLineIndex: initialLineIndex,
      selectedLineIndex: selectedLineIndex,
      measuredLineIndex: candidateIndex,
    );
    Log.i(
      '[ohos-auto-line] switch requested '
      'fromLine=${initialLineIndex + 1} toLine=${selectedLineIndex + 1} '
      'roomGeneration=$roomGeneration '
      'playbackRequestRevision=$playbackRequestRevision '
      'playerGeneration=$playerGeneration',
    );
    await changePlayLine(selectedLineIndex, persist: false);
  }

  void _refreshDanmakuOverlay(String reason) {
    if (!showDanmakuState.value) {
      return;
    }
    Log.d("$reason 后恢复弹幕覆盖层");
    danmakuController?.resume();
  }

  void _clearContributionRankState() {
    contributionRanks.clear();
    contributionRankFetched.value = false;
    contributionRankLoading.value = false;
    contributionRankError.value = null;
    contributionRankUpdatedAt.value = null;
  }

  void _startLiveEventFlowTimer() {
    _liveEventFlowTimer?.cancel();
    _liveEventFlowTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _flushLiveEventFlow(),
    );
  }

  void _recordLiveEventFlow(LiveMessage msg) {
    if (msg.userName == "LiveSysMessage") {
      return;
    }
    final settings = AppSettingsController.instance;
    if (!settings.liveEventFlowEnable.value) {
      _liveEventFlowAggregator.clear();
      liveEventFlows.clear();
      return;
    }
    final text = _normalizeMessageText(msg.message);
    if (text.isEmpty) {
      return;
    }
    _ensureLiveEventFlowAggregatorSettings();
    _liveEventFlowAggregator.add(text);
    _flushLiveEventFlow();
  }

  void _flushLiveEventFlow() {
    final settings = AppSettingsController.instance;
    if (!settings.liveEventFlowEnable.value) {
      _liveEventFlowAggregator.clear();
      liveEventFlows.clear();
      return;
    }
    _ensureLiveEventFlowAggregatorSettings();
    final summaries = _liveEventFlowAggregator.preview(
      displayTtl: Duration(
        seconds: settings.effectiveLiveEventFlowDisplaySeconds,
      ),
    );
    liveEventFlows.assignAll(summaries);
    final limit = settings.liveEventFlowLimit.value;
    if (liveEventFlows.length > limit) {
      liveEventFlows.removeRange(limit, liveEventFlows.length);
    }
  }

  void _ensureLiveEventFlowAggregatorSettings() {
    final settings = AppSettingsController.instance;
    final countWindow = Duration(
      seconds: settings.effectiveLiveEventFlowWindowSeconds,
    );
    final minDisplayCount = settings.effectiveLiveEventFlowMinCount;
    if (_liveEventFlowAggregator.countWindow == countWindow &&
        _liveEventFlowAggregator.minDisplayCount == minDisplayCount) {
      return;
    }
    _liveEventFlowAggregator = LiveRepeatedDanmuAggregator(
      countWindow: countWindow,
      minDisplayCount: minDisplayCount,
    );
    liveEventFlows.clear();
  }

  void clearLiveEventFlow() {
    _liveEventFlowAggregator.clear();
    liveEventFlows.clear();
  }

  Future<void> fetchContributionRank({bool forceRefresh = false}) async {
    if (!AppSettingsController.instance.contributionRankEnable.value ||
        !supportsContributionRank ||
        detail.value == null) {
      return;
    }
    if (contributionRankLoading.value) {
      return;
    }
    if (!forceRefresh &&
        contributionRanks.isNotEmpty &&
        contributionRankError.value == null) {
      return;
    }

    final requestSiteId = site.id;
    final requestRoomId = roomId;
    contributionRankLoading.value = true;
    contributionRankError.value = null;
    try {
      final ranks = await site.liveSite.getContributionRank(
        roomId: detail.value!.roomId,
        detail: detail.value,
      );
      if (site.id != requestSiteId || roomId != requestRoomId) {
        return;
      }
      contributionRanks.assignAll(ranks.map(_sanitizeContributionRankItem));
      contributionRankFetched.value = true;
      contributionRankUpdatedAt.value = DateTime.now();
    } catch (e) {
      Log.logPrint(e);
      if (site.id != requestSiteId || roomId != requestRoomId) {
        return;
      }
      contributionRankError.value = e.toString();
    } finally {
      if (site.id == requestSiteId && roomId == requestRoomId) {
        contributionRankLoading.value = false;
      }
    }
  }

  /// 初始化自动关闭计时器
  void initAutoExit() {
    autoExitEnable.value = AppSettingsController.instance.autoExitEnable.value;
    autoExitMinutes.value =
        AppSettingsController.instance.roomAutoExitDuration.value;
    countdown.value = autoExitMinutes.value * 60;
    if (autoExitEnable.value) {
      setAutoExit();
    }
  }

  void setAutoExit() {
    if (!autoExitEnable.value) {
      autoExitTimer?.cancel();
      _autoExitDeadline = null;
      return;
    }
    autoExitTimer?.cancel();
    _autoExitCompleting = false;
    _autoExitDeadline =
        DateTime.now().add(Duration(minutes: autoExitMinutes.value));
    _refreshAutoExitCountdown();
    autoExitTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshAutoExitCountdown(),
    );
  }

  void _refreshAutoExitCountdown() {
    final deadline = _autoExitDeadline;
    if (!autoExitEnable.value || deadline == null) {
      return;
    }
    final remaining = deadline.difference(DateTime.now());
    countdown.value = remaining.isNegative ? 0 : remaining.inSeconds + 1;
    if (remaining <= Duration.zero) {
      unawaited(_completeAutoExit());
    }
  }

  Future<void> _completeAutoExit() async {
    if (_autoExitCompleting) {
      return;
    }
    _autoExitCompleting = true;
    autoExitTimer?.cancel();
    _autoExitDeadline = null;
    countdown.value = 0;
    try {
      Log.i(
          "定时关闭到点：platform=${Platform.operatingSystem} room=${site.id}/$roomId");
      autoExitEnable.value = false;
      await AppSettingsController.instance.setAutoExitEnable(false);
      await cancelAutoPipOnLeave();
      await stopBackgroundPlaybackService();
      await liveDanmaku.stop();
      if (!Utils.isOhos) {
        await player.stop();
      }
      if (!Utils.isOhos) {
        setPlaybackKeepScreenAwake(false);
      }
      if (Utils.isOhos) {
        await closePlayerResources();
        await SystemNavigator.pop();
      } else if (Platform.isIOS) {
        if (fullScreenState.value || smallWindowState.value) {
          await exitPlayerWindowMode();
        }
        Get.offAllNamed(RoutePath.kIndex);
      } else if (Platform.isAndroid) {
        await SystemNavigator.pop();
      } else {
        if (Platform.isWindows) {
          await windowManager.setPreventClose(false);
        }
        await windowManager.close();
      }
    } catch (e, stackTrace) {
      Log.e("执行定时关闭失败: $e", stackTrace);
    }
  }

  void stopAutoExit() {
    autoExitEnable.value = false;
    autoExitTimer?.cancel();
    _autoExitDeadline = null;
    countdown.value = autoExitMinutes.value * 60;
  }

  Future<bool> syncAutoPipOnLeave() async {
    if (_autoPipAttempting) {
      return false;
    }
    if (!(Platform.isAndroid || Utils.isOhos) ||
        !AppSettingsController.instance.autoPipOnExit.value ||
        !liveStatus.value) {
      if (Platform.isAndroid || Utils.isOhos) {
        await cancelAutoPipOnLeave();
      }
      return false;
    }
    _autoPipAttempting = true;
    try {
      return await prepareAutoPipOnLeave();
    } catch (e) {
      Log.d("配置退后台自动小窗失败: $e");
      return false;
    } finally {
      _autoPipAttempting = false;
    }
  }
  // 页面刷新与重载逻辑

  void refreshRoom() {
    if (kuaishouRefreshBlocked) {
      SmartDialog.showToast(
        '请求冷却中，请等待 ${formatKuaishouRecoveryCountdown(kuaishouRecoveryRemainingSeconds.value)}',
      );
      return;
    }
    _cancelKuaishouDeviceRecoveryTimer();
    //messages.clear();
    _clearDanmuDedupeState();
    _clearSuperChatState();
    _clearContributionRankState();
    clearLiveEventFlow();
    liveDanmaku.stop();
    if (detail.value != null) {
      getSuperChatMessage();
    }

    _resetPlaybackHealthSession();
    loadData();
  }

  Future<void> rebuildKuaishouDeviceSession() async {
    final rateLimitError = error;
    if (rateLimitError is! KuaishouRateLimitError ||
        !Get.isRegistered<KuaishouAccountService>()) {
      return;
    }
    final rebuilt = KuaishouAccountService.instance.rebuildDeviceSessions(
      rateLimitError.rateLimitedSessionKeys,
    );
    if (rebuilt.isEmpty) {
      kuaishouDeviceRecoveryAvailable.value = false;
      SmartDialog.showToast('今天已重建过设备会话，请稍后再试或重新登录');
      return;
    }
    kuaishouDeviceRecoveryAvailable.value = false;
    kuaishouDeviceRecoveryArmed.value = true;
    _kuaishouDeviceRecoveryRoomKey = '${site.id}:${rxRoomId.value}';
    _kuaishouDeviceRecoverySlot = rebuilt.first;
    _startKuaishouDeviceRecoveryCountdown(rateLimitError.cooldownUntil);
  }

  void _configureKuaishouDeviceRecovery(Object caughtError) {
    _cancelKuaishouDeviceRecoveryTimer(clearState: true);
    if (caughtError is! KuaishouRateLimitError ||
        !Get.isRegistered<KuaishouAccountService>()) {
      return;
    }
    final account = KuaishouAccountService.instance;
    kuaishouDeviceRecoveryAvailable.value = caughtError.rateLimitedSessionKeys
        .map(
          (key) => KuaishouAccountSlot.values.firstWhereOrNull(
            (slot) => slot.name == key,
          ),
        )
        .whereType<KuaishouAccountSlot>()
        .any((slot) => account.canRebuildDeviceSession(slot));
    _startKuaishouDeviceRecoveryCountdown(caughtError.cooldownUntil);
  }

  void _startKuaishouDeviceRecoveryCountdown(DateTime? cooldownUntil) {
    _kuaishouDeviceRecoveryTimer?.cancel();
    _updateKuaishouRecoveryRemaining(cooldownUntil);
    if (kuaishouRecoveryRemainingSeconds.value <= 0) {
      _retryKuaishouAfterDeviceRecovery();
      return;
    }
    _kuaishouDeviceRecoveryTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        _updateKuaishouRecoveryRemaining(cooldownUntil);
        if (kuaishouRecoveryRemainingSeconds.value <= 0) {
          _retryKuaishouAfterDeviceRecovery();
        }
      },
    );
  }

  void _updateKuaishouRecoveryRemaining(DateTime? cooldownUntil) {
    if (cooldownUntil == null) {
      kuaishouRecoveryRemainingSeconds.value = 0;
      return;
    }
    final remainingMilliseconds =
        cooldownUntil.difference(DateTime.now()).inMilliseconds;
    final remaining =
        remainingMilliseconds <= 0 ? 0 : (remainingMilliseconds + 999) ~/ 1000;
    kuaishouRecoveryRemainingSeconds.value = remaining > 0 ? remaining : 0;
  }

  void _retryKuaishouAfterDeviceRecovery() {
    _kuaishouDeviceRecoveryTimer?.cancel();
    _kuaishouDeviceRecoveryTimer = null;
    final recoveryRoomKey = _kuaishouDeviceRecoveryRoomKey;
    final recoverySlot = _kuaishouDeviceRecoverySlot;
    final shouldRetry = shouldAutoRetryKuaishouDeviceRecovery(
      roomDisposed: _roomDisposed,
      armed: kuaishouDeviceRecoveryArmed.value,
      recoveryRoomKey: recoveryRoomKey,
      currentRoomKey: '${site.id}:${rxRoomId.value}',
    );
    kuaishouDeviceRecoveryArmed.value = false;
    _kuaishouDeviceRecoveryRoomKey = null;
    _kuaishouDeviceRecoverySlot = null;
    kuaishouRecoveryRemainingSeconds.value = 0;
    if (!shouldRetry) return;
    if (recoverySlot != null && Get.isRegistered<KuaishouAccountService>()) {
      final activated =
          KuaishouAccountService.instance.activateRebuiltSession(recoverySlot);
      if (!activated) return;
    }
    refreshRoom();
  }

  void _cancelKuaishouDeviceRecoveryTimer({bool clearState = false}) {
    _kuaishouDeviceRecoveryTimer?.cancel();
    _kuaishouDeviceRecoveryTimer = null;
    kuaishouDeviceRecoveryArmed.value = false;
    _kuaishouDeviceRecoveryRoomKey = null;
    _kuaishouDeviceRecoverySlot = null;
    if (clearState) {
      kuaishouRecoveryRemainingSeconds.value = 0;
      kuaishouDeviceRecoveryAvailable.value = false;
    }
  }

  @override
  void onPlayerWindowModeExited() {
    forceChatScrollToBottom(delay: const Duration(milliseconds: 120));
  }

  @override
  Future<void> enterSmallWindow() async {
    await closeFollowHoldPreview();
    await super.enterSmallWindow();
  }

  @override
  Future<bool> prepareAutoPipOnLeave() async {
    await closeFollowHoldPreview();
    return super.prepareAutoPipOnLeave();
  }

  @override
  Future<dynamic> enablePIP() async {
    await closeFollowHoldPreview();
    return super.enablePIP();
  }

  @override
  Future<void> closePlayerResources() async {
    if (!_roomDisposed) {
      await closeFollowHoldPreview();
    }
    await super.closePlayerResources();
  }

  @override
  void onClose() async {
    _roomDisposed = true;
    await closeFollowHoldPreview();
    await _holdPreviewMutations.close();
    _hasActivePlaybackSession = false;
    waitingForPlaybackUrl.value = false;
    _loadGeneration += 1;
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isWindows) {
      windowManager.removeListener(this);
    }
    unawaited(cancelAutoPipOnLeave());
    CurrentRoomService.instance.clearRoom();
    scrollController.removeListener(scrollListener);
    liveRoomFollowScrollController.dispose();
    liveRoomFollowDialogScrollController.dispose();
    liveRoomHistoryScrollController.dispose();
    liveRoomRecommendationScrollController.dispose();
    autoExitTimer?.cancel();
    _autoQualityBufferingSubscription?.cancel();
    _ohosReconnectConfirmationTimer?.cancel();
    _ohosReconnectConfirmationTimer = null;
    _ohosReconnectConfirmation.reset();
    _resetKuaishouPlaybackRecoverySession();
    _superChatRefreshTimer?.cancel();
    _liveEventFlowTimer?.cancel();
    _onlineRefreshTimer?.cancel();
    _cancelKuaishouDeviceRecoveryTimer(clearState: true);
    _stopLiveLatencyTelemetry();
    _chatBottomRestoreTimer?.cancel();
    _cancelPendingDanmakuTimers();
    clearDanmakuReplayHistory();
    _liveDurationTimer?.cancel();
    _positionSubscription?.cancel();
    unawaited(
      AppSettingsController.instance.setLastLiveRoomResumePending(false),
    );
    if (!Utils.isOhos && !isPlayerClosing) {
      await player.stop();
    }
    await liveDanmaku.stop();
    super.onClose();
  }

  /// 聊天列表滚动到底部
  void chatScrollToBottom() {
    if (scrollController.hasClients) {
      // 用户手动上拉过时，不再自动滚到底部。
      if (disableAutoScroll.value) {
        return;
      }
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
    }
  }

  void forceChatScrollToBottom({Duration delay = Duration.zero}) {
    _chatBottomRestoreTimer?.cancel();
    _chatBottomRestoreTimer = Timer(delay, () {
      disableAutoScroll.value = false;
      if (!scrollController.hasClients) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) {
          return;
        }
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
      });
    });
  }

  /// 初始化弹幕连接回调
  void initDanmau() {
    liveDanmaku.onMessage = onWSMessage;
    liveDanmaku.onClose = onWSClose;
    liveDanmaku.onReady = onWSReady;
  }

  /// 接收 WebSocket 消息
  void onWSMessage(LiveMessage msg) {
    msg = _sanitizeLiveMessage(msg);
    if (msg.type == LiveMessageType.chat) {
      if (_isUserShielded(msg.userName) || isTempMutedUser(msg.userName)) {
        Log.d("已过滤被屏蔽用户: ${msg.userName}");
        return;
      }

      if (_isKeywordShielded(msg)) {
        return;
      }

      _recordLiveEventFlow(msg);

      if (_isDuplicateDanmu(msg)) {
        return;
      }

      messages.add(msg);

      // 在屏蔽/去重过滤并添加之后按独立上限截断，与是否自动滚动无关，
      // 保证过滤后列表长度有界，避免 disableAutoScroll 时内存无上限。
      if (messages.length > 500) {
        messages.removeRange(0, messages.length - 500);
      }

      WidgetsBinding.instance.addPostFrameCallback(
        (_) => chatScrollToBottom(),
      );
      if (!liveStatus.value || (isBackground && !_allowBackgroundPlayback)) {
        return;
      }
      _scheduleOverlayDanmaku(msg);
      return;
    } else if (msg.type == LiveMessageType.online) {
      online.value = msg.data;
    } else if (msg.type == LiveMessageType.superChat) {
      if (msg.data is! LiveSuperChatMessage) {
        return;
      }
      final superChat =
          _sanitizeSuperChatMessage(msg.data as LiveSuperChatMessage);
      if (_isUserShielded(superChat.userName) ||
          isTempMutedUser(superChat.userName)) {
        return;
      }
      if (_isKeywordShielded(_superChatToLiveMessage(superChat))) {
        return;
      }
      _appendSuperChats([superChat]);
      return;
    }
  }

  /// 添加一条系统消息
  void addSysMsg(String msg) {
    messages.add(
      LiveMessage(
        type: LiveMessageType.chat,
        userName: "LiveSysMessage",
        message: _normalizeMessageText(msg),
        color: LiveMessageColor.white,
      ),
    );
  }

  /// 接收 WebSocket 关闭消息
  void onWSClose(String msg) {
    addSysMsg(msg);
  }

  /// WebSocket 已连接完成
  void onWSReady() {
    addSysMsg("弹幕服务器连接成功");
  }

  /// 加载直播间信息
  void loadData() async {
    final loadGeneration = ++_loadGeneration;
    _resetOhosAutoLineSelectionSession();
    final loadStopwatch = Stopwatch()..start();
    _dismissLiveRoomLoadingOverlay();
    try {
      loadError.value = false;
      error = null;
      errorStackTrace = null;
      _onlineRefreshTimer?.cancel();
      roomLiveState.value = LiveStatusState.unknown;
      offlineConfirmations.value = 0;
      waitingForPlaybackUrl.value = false;
      _kuaishouNoCookieHintShown = false;
      _hasActivePlaybackSession = false;
      _playbackBootstrapInFlight = false;
      liveStatus.value = false;
      update();
      await liveDanmaku.stop();
      liveDanmaku = site.liveSite.getDanmaku();
      _clearContributionRankState();
      _clearSuperChatState();
      _cancelPendingDanmakuTimers();
      clearDanmakuReplayHistory();
      rebuildDanmakuView();
      addSysMsg("正在读取直播间信息");
      final detailStopwatch = Stopwatch()..start();
      final detailRequest = _fetchRoomDetailWithSource(
        source: site.id == Constant.kKuaishou
            ? KuaishouRequestSource.userEnter
            : null,
      );
      final roomDetail = _sanitizeRoomDetail(
        site.id == Constant.kKuaishou
            ? await detailRequest.timeout(const Duration(seconds: 12))
            : await detailRequest,
      );
      detailStopwatch.stop();
      Log.i(
        "读取直播间信息完成：${site.id}/$roomId ${detailStopwatch.elapsedMilliseconds}ms",
      );
      if (!_isCurrentLoad(loadGeneration)) {
        return;
      }
      detail.value = roomDetail;
      addSysMsg("直播间信息读取完成");
      _syncBackgroundPlaybackMetadata(roomDetail);

      if (site.id == Constant.kDouyin) {
        // 1.6.0 之前收藏的是 WebRid，中间一版收藏的是 RoomID，
        // 这里统一修正回当前实际 roomId。
        if (detail.value!.roomId != roomId) {
          var oldId = roomId;
          final resolvedRoomId = detail.value!.roomId;
          rxRoomId.value = detail.value!.roomId;
          if (followed.value) {
            // 同步修正已关注房间的主键
            DBService.instance.deleteFollow("${site.id}_$oldId");
            DBService.instance.addFollow(
              FollowUser(
                id: "${site.id}_$resolvedRoomId",
                roomId: resolvedRoomId,
                siteId: site.id,
                userName: detail.value!.userName,
                face: detail.value!.userAvatar,
                addTime: DateTime.now(),
              ),
            );
          } else {
            followed.value = DBService.instance.getFollowExist(
              "${site.id}_$resolvedRoomId",
            );
          }
        }
      }
      unawaited(
        AppSettingsController.instance.saveLastLiveRoom(
          siteId: site.id,
          roomId: roomId,
        ),
      );

      getSuperChatMessage();
      if (AppSettingsController.instance.contributionRankEnable.value) {
        fetchContributionRank();
      }
      if (!_isCurrentLoad(loadGeneration)) {
        return;
      }

      addHistory();
      unawaited(
        FollowService.instance.syncFollowStatusFromRoomDetail(
          detail.value!,
          siteId: site.id,
        ),
      );
      // 刷新关注状态
      followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");
      final initialLiveState = detail.value!.resolvedLiveStatus;
      if (initialLiveState != LiveStatusState.unknown) {
        online.value = detail.value!.online;
      }
      _applyRoomLiveState(initialLiveState);
      _restartSuperChatRefreshTimer();
      _restartOnlineRefreshTimer();
      unawaited(syncAutoPipOnLeave());
      if (initialLiveState == LiveStatusState.live) {
        unawaited(_bootstrapPlaybackIfNeeded());
      }
      if (detail.value!.isRecord) {
        addSysMsg("当前主播未开播，正在转播录像");
      }
      if (_kuaishouNoCookie) {
        addSysMsg("快手未登录（无 Cookie），弹幕不可用");
        addSysMsg("可在「我的 → 账号管理」登录快手账号后重试");
      } else {
        addSysMsg("正在连接弹幕服务器");
      }
      if (!_isCurrentLoad(loadGeneration)) {
        return;
      }
      initDanmau();
      unawaited(liveDanmaku.start(detail.value?.danmakuData));
      startLiveDurationTimer();
    } catch (e, stackTrace) {
      Log.logPrint(e);
      //SmartDialog.showToast(e.toString());
      if (!_isCurrentLoad(loadGeneration)) {
        return;
      }
      if (site.id == Constant.kKuaishou) {
        // S2-T3：详情失败与播放地址未就绪分离。
        // 明确限流/风控（403/429）显示可重试错误；其他失败静默恢复轮询，
        // 避免黑屏转圈（保持冷启动方案 5.1 的恢复语义）。
        final isHttpLimit = e is CoreError &&
            (e.kind == CoreErrorKind.http) &&
            (e.statusCode == 403 || e.statusCode == 429);
        if (isHttpLimit) {
          roomLiveState.value = LiveStatusState.unknown;
          offlineConfirmations.value = 0;
          loadError.value = true;
          error = e;
          errorStackTrace = stackTrace;
          Log.w("快手详情请求被限流(${e.statusCode})，显示可重试错误");
        } else {
          roomLiveState.value = LiveStatusState.unknown;
          offlineConfirmations.value = 0;
          loadError.value = true;
          error = e;
          errorStackTrace = stackTrace;
        }
      } else {
        loadError.value = true;
        error = e;
        errorStackTrace = stackTrace;
      }
      _configureKuaishouDeviceRecovery(e);
    } finally {
      _dismissLiveRoomLoadingOverlay();
      loadStopwatch.stop();
      Log.i(
        "直播间加载流程结束：${site.id}/$roomId ${loadStopwatch.elapsedMilliseconds}ms",
      );
    }
  }

  void _dismissLiveRoomLoadingOverlay() {
    unawaited(SmartDialog.dismiss(status: SmartStatus.loading));
  }

  bool _isCurrentLoad(int loadGeneration) {
    return !_roomDisposed && loadGeneration == _loadGeneration;
  }

  /// 读取可用清晰度并选择默认值
  Future<void> getPlayQualites() async {
    final loadGeneration = _loadGeneration;
    qualites.clear();
    currentQuality = -1;

    try {
      var playQualites =
          await site.liveSite.getPlayQualites(detail: detail.value!);
      if (!_isCurrentLoad(loadGeneration)) {
        return;
      }

      if (playQualites.isEmpty) {
        if (site.id == Constant.kKuaishou &&
            roomLiveState.value == LiveStatusState.live) {
          waitingForPlaybackUrl.value = true;
          _showKuaishouNoCookiePlaybackHint();
          Log.d("快手直播已开播，播放地址尚未就绪，等待后续轮询");
          return;
        }
        final qualityError = CoreError("无法读取播放清晰度，请稍后重试");
        Log.e(
          "播放清晰度列表为空：${site.id}/$roomId generation=$loadGeneration",
          StackTrace.current,
        );
        loadError.value = true;
        error = qualityError;
        errorStackTrace = StackTrace.current;
        return;
      }
      // Site implementations may return a fixed-length list. RxList is
      // mutated later during a URL reload, so keep an owned growable copy.
      qualites.value = List<LivePlayQuality>.of(playQualites);
      final preference = _loadQualityPreference();
      qualityLocked.value = preference.qualityLocked;
      currentQuality = resolveInitialLiveRoomQualityIndex(
        qualityCount: playQualites.length,
        qualityLevel: await getQualityLevel(),
        preference: preference,
      );
      currentQualityInfo.value = qualites[currentQuality].quality;

      await getPlayUrl();
    } catch (e, stackTrace) {
      if (!_isCurrentLoad(loadGeneration)) {
        return;
      }
      Log.e(
        "读取播放清晰度失败：${site.id}/$roomId generation=$loadGeneration error=$e",
        stackTrace,
      );
      if (site.id == Constant.kKuaishou &&
          roomLiveState.value == LiveStatusState.live) {
        waitingForPlaybackUrl.value = true;
        return;
      }
      loadError.value = true;
      error = e;
      errorStackTrace = stackTrace;
    }
  }

  Future<int> getQualityLevel() async {
    var qualityLevel = AppSettingsController.instance.qualityLevel.value;
    try {
      if (Utils.isOhos) {
        final networkType = await OhosNetworkService.getNetworkType();
        if (networkType == OhosNetworkType.cellular) {
          qualityLevel =
              AppSettingsController.instance.qualityLevelCellular.value;
        }
        return qualityLevel;
      }
      var connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult == ConnectivityResult.mobile) {
        qualityLevel =
            AppSettingsController.instance.qualityLevelCellular.value;
      }
    } catch (e) {
      Log.logPrint(e);
    }
    return qualityLevel;
  }

  bool _isCurrentPlaybackRequest(int requestRevision, int loadGeneration) {
    return !_roomDisposed &&
        isCurrentLiveRoomPlaybackRequest(
          roomGeneration: _loadGeneration,
          expectedRoomGeneration: loadGeneration,
          requestRevision: requestRevision,
          latestRequestRevision: _playbackRequestRevision,
        );
  }

  Future<bool> _reloadPlayUrls({
    required int requestRevision,
    bool resetLine = false,
    bool silent = false,
  }) async {
    final loadGeneration = _loadGeneration;
    if (_roomDisposed) {
      return false;
    }
    if (detail.value == null ||
        currentQuality < 0 ||
        currentQuality >= qualites.length) {
      return false;
    }
    currentQualityInfo.value = qualites[currentQuality].quality;
    var playUrl = await site.liveSite
        .getPlayUrls(detail: detail.value!, quality: qualites[currentQuality]);
    if (!_isCurrentPlaybackRequest(requestRevision, loadGeneration)) {
      return false;
    }
      if (playUrl.urls.isEmpty) {
        if (site.id == Constant.kKuaishou &&
            roomLiveState.value == LiveStatusState.live) {
          waitingForPlaybackUrl.value = true;
          _showKuaishouNoCookiePlaybackHint();
        } else if (!silent) {
        SmartDialog.showToast("无法读取播放地址");
      }
      return false;
    }
    // Keep the observable list mutable: some site parsers return a fixed-
    // length list and the next quality/line reload clears this list first.
    final nextPlayUrls = List<String>.of(
      sortLiveStreamUrlsByLatency(playUrl.urls),
    );
    var nextLineIndex = currentLineIndex;
    if (resetLine || currentLineIndex < 0) {
      final bestLineIndices = lowestLatencyLineIndices(nextPlayUrls);
      final autoSelect =
          AppSettingsController.instance.autoSelectFastestLine.value;
      nextLineIndex = bestLineIndices.first;
      if (!autoSelect) {
        final remembered = resolveRememberedLiveRoomLineIndex(
          urls: nextPlayUrls,
          preference: _loadQualityPreference(),
        );
        if (remembered != null) {
          nextLineIndex = remembered;
        }
      }
    } else if (currentLineIndex >= nextPlayUrls.length) {
      nextLineIndex = nextPlayUrls.length - 1;
    }
    if (!_isCurrentPlaybackRequest(requestRevision, loadGeneration)) {
      return false;
    }
    waitingForPlaybackUrl.value = false;
    playUrls.value = nextPlayUrls;
    playHeaders = playUrl.headers;
    currentLineIndex = nextLineIndex;
    currentLineInfo.value = lineDisplayName(currentLineIndex);
    return true;
  }

  /// Kuaishou playback URLs live in LivePlayQuality.data rather than solely in
  /// the room detail. Refresh both snapshots before resolving a replacement
  /// line, and keep the previous snapshot when the refresh cannot produce a
  /// usable URL.
  Future<bool> _reloadKuaishouPlaybackUrls({
    required int requestRevision,
  }) async {
    final loadGeneration = _loadGeneration;
    if (site.id != Constant.kKuaishou ||
        detail.value == null ||
        !_isCurrentPlaybackRequest(requestRevision, loadGeneration)) {
      return false;
    }

    final previousDetail = detail.value!;
    final previousOnline = online.value;
    final previousQualities = List<LivePlayQuality>.of(qualites);
    final previousQuality = currentQuality;
    final previousQualityInfo = currentQualityInfo.value;
    final previousPlayUrls = List<String>.of(playUrls);
    final previousPlayHeaders = playHeaders;
    final previousLineIndex = currentLineIndex;
    final previousLineUrl =
        previousLineIndex >= 0 && previousLineIndex < previousPlayUrls.length
            ? previousPlayUrls[previousLineIndex]
            : null;
    final previousLineInfo = currentLineInfo.value;
    final previousWaitingForPlaybackUrl = waitingForPlaybackUrl.value;
    final previousQualityName =
        previousQuality >= 0 && previousQuality < previousQualities.length
            ? previousQualities[previousQuality].quality
            : previousQualityInfo;
    var snapshotReplaced = false;

    void restorePreviousSnapshot() {
      detail.value = previousDetail;
      online.value = previousOnline;
      qualites.value = previousQualities;
      currentQuality = previousQuality;
      currentQualityInfo.value = previousQualityInfo;
      playUrls.value = previousPlayUrls;
      playHeaders = previousPlayHeaders;
      currentLineIndex = previousLineIndex;
      currentLineInfo.value = previousLineInfo;
      waitingForPlaybackUrl.value = previousWaitingForPlaybackUrl;
    }

    try {
      final fetchedDetail = _sanitizeRoomDetail(
        await _fetchRoomDetailWithSource(
          source: KuaishouRequestSource.playbackRecovery,
        ).timeout(const Duration(seconds: 12)),
      );
      if (!_isCurrentPlaybackRequest(requestRevision, loadGeneration)) {
        return false;
      }
      final freshDetail = mergeKuaishouRoomDetailMetadata(
        current: previousDetail,
        incoming: fetchedDetail,
      );
      final freshQualities = List<LivePlayQuality>.of(
        await site.liveSite.getPlayQualites(detail: freshDetail),
      );
      if (!_isCurrentPlaybackRequest(requestRevision, loadGeneration) ||
          freshQualities.isEmpty) {
        return false;
      }

      final nextQuality = resolveKuaishouRecoveryQualityIndex(
        qualities: [for (final quality in freshQualities) quality.quality],
        previousQualityName: previousQualityName,
        previousQualityIndex: previousQuality,
      );
      // No await occurs in this block: observers see either the old snapshot
      // or a complete fresh detail/quality pair.
      detail.value = freshDetail;
      online.value = freshDetail.online;
      qualites.value = freshQualities;
      currentQuality = nextQuality;
      currentQualityInfo.value = freshQualities[nextQuality].quality;
      snapshotReplaced = true;

      final reloaded = await _reloadPlayUrls(
        requestRevision: requestRevision,
        silent: true,
      );
      if (!_isCurrentPlaybackRequest(requestRevision, loadGeneration)) {
        return false;
      }
      if (reloaded) {
        currentLineIndex = resolveKuaishouRecoveryLineIndex(
          urls: playUrls,
          previousUrl: previousLineUrl,
          fallbackIndex: currentLineIndex,
        );
        currentLineInfo.value = lineDisplayName(currentLineIndex);
        return true;
      }

      // A failed fresh URL lookup must not discard the still-playable source.
      restorePreviousSnapshot();
      return false;
    } catch (e, stackTrace) {
      Log.e('快手刷新播放详情失败: $e', stackTrace);
      if (snapshotReplaced &&
          _isCurrentPlaybackRequest(requestRevision, loadGeneration)) {
        restorePreviousSnapshot();
      }
      return false;
    }
  }

  String? get _selectedPlaybackSource =>
      currentLineIndex >= 0 && currentLineIndex < playUrls.length
          ? playUrls[currentLineIndex]
          : null;

  Future<void> getPlayUrl({
    bool userInitiatedQualityChange = false,
    LiveReconnectReason? automaticReconnectReason,
  }) async {
    final previousSource = _selectedPlaybackSource;
    final reconnectStartedAt =
        automaticReconnectReason == null ? null : DateTime.now();
    final requestRevision = ++_playbackRequestRevision;
    final loadGeneration = _loadGeneration;
    playUrls.clear();
    currentLineInfo.value = "";
    currentLineIndex = -1;
    if (!await _reloadPlayUrls(
      requestRevision: requestRevision,
      resetLine: true,
    )) {
      return;
    }
    if (!_isCurrentPlaybackRequest(requestRevision, loadGeneration)) {
      return;
    }
    if (!_autoQualityWarmupStartedForRoom) {
      _autoQualityWarmupStartedForRoom = true;
      final now = DateTime.now();
      _autoQualityBufferTracker.beginWarmup(now);
      _ohosDegradeEvidence.beginWarmup(now);
      _kuaishouPlaybackRecoveryTracker.beginWarmup(now);
    }
    // 重置播放器错误重试次数
    mediaErrorRetryCount = 0;
    await initPlaylist(
      requestRevision: requestRevision,
      allowOhosAutoLineSelection:
          !userInitiatedQualityChange && automaticReconnectReason == null,
      ohosPlaybackRecovery: automaticReconnectReason != null,
    );
    if (_isCurrentPlaybackRequest(requestRevision, loadGeneration)) {
      if (userInitiatedQualityChange && _hasActivePlaybackSession) {
        recordLiveLinkHealthEvent(LiveLinkEventType.qualityChangedByUser);
      }
      if (automaticReconnectReason != null && reconnectStartedAt != null) {
        final hostChanged = didLivePlaybackHostChange(
          previousSource,
          _selectedPlaybackSource,
        );
        if (Utils.isOhos) {
          _armOhosReconnect(
            reason: automaticReconnectReason,
            hostChanged: hostChanged,
            startedAt: reconnectStartedAt,
          );
        } else {
          final completedAt = DateTime.now();
          recordLiveLinkHealthEvent(
            LiveLinkEventType.cdnReconnect,
            at: completedAt,
            reconnectReason: automaticReconnectReason,
            reconnectHostChanged: hostChanged,
            reconnectRecoveryDuration: completedAt.difference(
              reconnectStartedAt,
            ),
          );
        }
      }
      if (!Utils.isOhos) {
        _scheduleAutoSelectFastestLine(
          requestRevision: requestRevision,
          loadGeneration: loadGeneration,
        );
      }
    }
  }

  Future<void> changePlayLine(
    int index, {
    bool persist = true,
    LiveReconnectReason? reconnectReason,
  }) async {
    final loadGeneration = _loadGeneration;
    final reconnectHostChanged = reconnectReason == null
        ? null
        : didLivePlaybackHostChange(
            _selectedPlaybackSource,
            index >= 0 && index < playUrls.length ? playUrls[index] : null,
          );
    if (persist) {
      _manualLineSelectionRevision += 1;
      _ohosFailedLineIndices.clear();
    }
    currentLineIndex = index;
    if (persist) {
      saveQualityMemory(saveLine: true);
    }
    // 切线时同样重置重试次数
    mediaErrorRetryCount = 0;
    final reopened = await setPlayer(
      reconnectReason: reconnectReason,
      reconnectHostChanged: reconnectHostChanged,
      suppressOhosAutoLineSelection: persist,
    );
    if (!reopened || !_isCurrentLoad(loadGeneration)) {
      return;
    }
    if (persist) {
      recordLiveLinkHealthEvent(LiveLinkEventType.lineChangedByUser);
    }
  }

  void _scheduleAutoSelectFastestLine({
    required int requestRevision,
    required int loadGeneration,
  }) {
    if (Utils.isOhos ||
        !AppSettingsController.instance.autoSelectFastestLine.value ||
        !_hasActivePlaybackSession ||
        !_isCurrentPlaybackRequest(requestRevision, loadGeneration)) {
      return;
    }
    final candidateIndices = lowestLatencyLineIndices(playUrls);
    if (candidateIndices.length <= 1) {
      return;
    }
    final initialLineIndex = currentLineIndex;
    final manualSelectionRevision = _manualLineSelectionRevision;
    final candidates = [
      for (final index in candidateIndices) playUrls[index],
    ];
    Log.d(
      '播放器已开始打开，后台测速最低延迟协议档：'
      '${candidates.length} 条线路',
    );
    unawaited(
      _selectFastestLineAfterPlaybackStart(
        requestRevision: requestRevision,
        loadGeneration: loadGeneration,
        initialLineIndex: initialLineIndex,
        manualSelectionRevision: manualSelectionRevision,
        candidateIndices: candidateIndices,
        candidates: candidates,
      ),
    );
  }

  Future<void> _selectFastestLineAfterPlaybackStart({
    required int requestRevision,
    required int loadGeneration,
    required int initialLineIndex,
    required int manualSelectionRevision,
    required List<int> candidateIndices,
    required List<String> candidates,
  }) async {
    int fastest;
    try {
      fastest = await NetworkDiagnoseService.findFastestLine(candidates);
    } catch (e, stackTrace) {
      Log.e('后台线路测速失败: $e', stackTrace);
      return;
    }
    if (!AppSettingsController.instance.autoSelectFastestLine.value ||
        !_hasActivePlaybackSession ||
        !_isCurrentPlaybackRequest(requestRevision, loadGeneration) ||
        manualSelectionRevision != _manualLineSelectionRevision ||
        currentLineIndex != initialLineIndex) {
      return;
    }
    final candidateIndex = fastest.clamp(0, candidates.length - 1).toInt();
    final selectedLineIndex = candidateIndices[candidateIndex];
    if (selectedLineIndex == currentLineIndex) {
      return;
    }
    Log.i(
      '后台测速选择线路${selectedLineIndex + 1}，'
      '原线路${currentLineIndex + 1}',
    );
    await changePlayLine(selectedLineIndex, persist: false);
  }

  Future<void> initPlaylist({
    required int requestRevision,
    bool allowOhosAutoLineSelection = true,
    bool ohosPlaybackRecovery = false,
  }) async {
    final loadGeneration = _loadGeneration;
    if (_roomDisposed ||
        !_isCurrentPlaybackRequest(requestRevision, loadGeneration) ||
        currentLineIndex < 0 ||
        currentLineIndex >= playUrls.length) {
      return;
    }
    while (_playerReopenCompleter != null) {
      await _playerReopenCompleter!.future;
      if (!_isCurrentPlaybackRequest(requestRevision, loadGeneration)) {
        return;
      }
    }
    if (currentLineIndex < 0 || currentLineIndex >= playUrls.length) {
      return;
    }
    // Stop the shared lightweight sampler before either backend changes
    // source. Its generation gate prevents an older native read from being
    // accepted after this point.
    await resetLiveLatencyChase();
    if (!_isCurrentPlaybackRequest(requestRevision, loadGeneration)) {
      return;
    }
    // A previous room/line may have been a portrait stream. Reset the hint
    // for every backend until the newly opened source reports its dimensions.
    isVertical.value = false;
    if (Utils.isOhos) {
      currentLineInfo.value = lineDisplayName(currentLineIndex);
      errorMsg.value = "";
      final now = DateTime.now();
      _autoQualityBufferTracker.beginWarmup(now);
      _ohosDegradeEvidence.beginWarmup(now);
      await startLivePlaybackLightweightSampling(
        source: playUrls[currentLineIndex],
      );
      _ohosHealthyPlaybackSince = null;
      _lastOhosPlaybackPosition = Duration.zero;
      // 新的一代播放器拥有全新的时钟：旧心跳会把“从未起播”伪装成健康。
      _ohosLastHeartbeatAt = null;
      resetOhosNativeHeartbeat();
      final nextPlayerGeneration = ohosPlayerRevision.value + 1;
      final assigned = _ohosPlaybackSignalAdapter.beginSource(
        roomGeneration: loadGeneration,
        playerGeneration: nextPlayerGeneration,
        source: currentNetworkDiagnosePlaybackUrl,
        at: now,
      );
      Log.d(
        'OHOS playback signal=${assigned.type.name} '
        'roomGeneration=${assigned.roomGeneration} '
        'playerGeneration=${assigned.playerGeneration} '
        'source=${assigned.sourceFingerprint}',
      );
      _ohosPlayerLoadGeneration = loadGeneration;
      _ohosPlayerRequestRevision = requestRevision;
      _ohosCurrentPlayerAllowsAutoLineSelection = allowOhosAutoLineSelection;
      _ohosPlayerStartedDuringRecovery = ohosPlaybackRecovery;
      ohosPlayerRevision.value = nextPlayerGeneration;
      _hasActivePlaybackSession = true;
      waitingForPlaybackUrl.value = false;
      if (site.id == Constant.kKuaishou) {
        _restartOnlineRefreshTimer();
      }
      return;
    }
    final reopenCompleter = Completer<void>();
    _playerReopenCompleter = reopenCompleter;
    try {
      currentLineInfo.value = lineDisplayName(currentLineIndex);
      errorMsg.value = "";

      var finalUrl = playUrls[currentLineIndex];
      if (AppSettingsController.instance.playerForceHttps.value) {
        finalUrl = finalUrl.replaceAll("http://", "https://");
      }
      final streamProtocol = classifyLiveStreamProtocol(finalUrl);
      _stopLiveLatencyTelemetry();

      final previousWidth = player.state.width;
      final previousHeight = player.state.height;
      final wasPlaying = player.state.playing;
      Log.i(
        "准备打开播放器：target=${site.id}/$roomId "
        "quality=${currentQualityInfo.value} line=${currentLineIndex + 1}/${playUrls.length} "
        "protocol=${streamProtocol.label} "
        "previousPlaying=$wasPlaying previousSize=${previousWidth}x$previousHeight "
        "${MpvOptionsService.diagnosticsSummary()}",
      );

      // 重新初始化播放器，并带上当前线路的请求头。
      final openStopwatch = Stopwatch()..start();
      await initializePlayer();
      if (!_isCurrentPlaybackRequest(requestRevision, loadGeneration)) {
        return;
      }
      await MpvOptionsService.applyLiveLatencyOptions(player, streamProtocol);

      await _stopDesktopPlayerBeforeOpen();
      if (!_isCurrentPlaybackRequest(requestRevision, loadGeneration)) {
        return;
      }

      // 每次真实开流都重新判定音频输出，避免切线路/改画质后残留上一次的失败标记。
      audioOutputFailed.value = false;
      // Warmup 必须覆盖 player.open() 期间产生的起播 buffering 事件。
      markStreamOpening();
      await player.open(
        Media(
          finalUrl,
          httpHeaders: playHeaders,
        ),
      );
      if (!_isCurrentPlaybackRequest(requestRevision, loadGeneration)) {
        if (!Utils.isOhos) {
          await player.stop();
        }
        return;
      }
      await startLivePlaybackLightweightSampling(source: finalUrl);
      if (!_isCurrentPlaybackRequest(requestRevision, loadGeneration)) {
        return;
      }
      _hasActivePlaybackSession = true;
      waitingForPlaybackUrl.value = false;
      // 播放已建立：快手改为重启分钟级低频复核，而不是完全停掉轮询。
      if (site.id == Constant.kKuaishou) {
        _restartOnlineRefreshTimer();
      }
      openStopwatch.stop();
      Log.i(
        "播放器打开完成：${site.id}/$roomId ${openStopwatch.elapsedMilliseconds}ms "
        "line=${currentLineIndex + 1}/${playUrls.length} "
        "protocol=${streamProtocol.label} "
        "size=${player.state.width}x${player.state.height}",
      );
      _startLiveLatencyTelemetry(
        protocol: streamProtocol,
        requestRevision: requestRevision,
        loadGeneration: loadGeneration,
      );
    } finally {
      if (identical(_playerReopenCompleter, reopenCompleter)) {
        _playerReopenCompleter = null;
      }
      reopenCompleter.complete();
    }
  }

  void _startLiveLatencyTelemetry({
    required LiveStreamProtocol protocol,
    required int requestRevision,
    required int loadGeneration,
  }) {
    _stopLiveLatencyTelemetry();
    final openedAt = DateTime.now();
    unawaited(
      _sampleLiveLatencyTelemetry(
        protocol: protocol,
        openedAt: openedAt,
        requestRevision: requestRevision,
        loadGeneration: loadGeneration,
      ),
    );
    _liveLatencyTelemetryTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(
        _sampleLiveLatencyTelemetry(
          protocol: protocol,
          openedAt: openedAt,
          requestRevision: requestRevision,
          loadGeneration: loadGeneration,
        ),
      ),
    );
  }

  void _stopLiveLatencyTelemetry() {
    _liveLatencyTelemetryTimer?.cancel();
    _liveLatencyTelemetryTimer = null;
    _liveLatencyTelemetryTracker.reset();
  }

  Future<void> _sampleLiveLatencyTelemetry({
    required LiveStreamProtocol protocol,
    required DateTime openedAt,
    required int requestRevision,
    required int loadGeneration,
  }) async {
    if (_liveLatencyTelemetryInFlight ||
        _roomDisposed ||
        !_hasActivePlaybackSession ||
        !_isCurrentPlaybackRequest(requestRevision, loadGeneration)) {
      return;
    }
    _liveLatencyTelemetryInFlight = true;
    try {
      final state = player.state;
      final nativeProperties = await sampleMpvLiveLatencyProperties(
        player,
        demuxerCacheDurationOverride: latestLivePlaybackCacheTelemetry,
      );
      if (_roomDisposed ||
          !_isCurrentPlaybackRequest(requestRevision, loadGeneration)) {
        return;
      }
      final sample = LiveLatencyTelemetrySample(
        wallClock: DateTime.now(),
        position: state.position,
        playing: state.playing,
        buffering: state.buffering,
        nativeProperties: nativeProperties,
      );
      Log.writeLog(
        formatLiveLatencyTelemetry(
          target: '${site.id}/$roomId',
          lineIndex: currentLineIndex,
          lineCount: playUrls.length,
          protocol: protocol.label,
          elapsed: sample.wallClock.difference(openedAt),
          sample: sample,
          delta: _liveLatencyTelemetryTracker.record(sample),
        ),
      );
    } finally {
      _liveLatencyTelemetryInFlight = false;
    }
  }

  Future<void> _stopDesktopPlayerBeforeOpen() async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return;
    }
    if (!player.state.playing && player.state.playlist.medias.isEmpty) {
      return;
    }
    try {
      await player.stop();
      await Future.delayed(const Duration(milliseconds: 120));
    } catch (e, stackTrace) {
      Log.e("切换直播间前停止旧播放失败: $e", stackTrace);
    }
  }

  Future<bool> setPlayer({
    bool refreshUrls = false,
    bool rotateOhosLine = false,
    LiveReconnectReason? reconnectReason,
    bool? reconnectHostChanged,
    bool suppressOhosAutoLineSelection = false,
  }) async {
    if (!_holdPreviewPromotingMain &&
        _holdPreviewPhase != LiveRoomHoldPreviewPhase.closed) {
      await closeFollowHoldPreview();
    }
    final previousSource = _selectedPlaybackSource;
    final reconnectStartedAt =
        reconnectReason == null && !refreshUrls ? null : DateTime.now();
    final requestRevision = ++_playbackRequestRevision;
    final loadGeneration = _loadGeneration;
    var playbackUrlRefreshed = false;
    try {
      if (refreshUrls) {
        final previousLineIndex = currentLineIndex;
        final reloaded = site.id == Constant.kKuaishou
            ? await _reloadKuaishouPlaybackUrls(
                requestRevision: requestRevision,
              )
            : await _reloadPlayUrls(
                requestRevision: requestRevision,
                silent: true,
              );
        if (!_isCurrentPlaybackRequest(requestRevision, loadGeneration)) {
          return false;
        }
        if (!reloaded) {
          // The old source is still worth reopening when the platform API is
          // temporarily unavailable. Returning here leaves the errored widget
          // on screen forever and prevents the next watchdog retry.
          Log.d("刷新播放地址失败，回退为重新打开当前线路");
        } else if (rotateOhosLine && Utils.isOhos && playUrls.length > 1) {
          playbackUrlRefreshed = true;
          // A fresh URL from the same CDN can still point to the unhealthy edge
          // node. On the second retry, move to another source before reopening.
          currentLineIndex = (previousLineIndex + 1) % playUrls.length;
          currentLineInfo.value = lineDisplayName(currentLineIndex);
          Log.d("鸿蒙播放恢复切换到线路${currentLineIndex + 1}");
        } else {
          playbackUrlRefreshed = true;
        }
      }
      if (currentLineIndex < 0 || currentLineIndex >= playUrls.length) {
        return false;
      }
      _hasActivePlaybackSession = false;
      await initPlaylist(
        requestRevision: requestRevision,
        allowOhosAutoLineSelection: !suppressOhosAutoLineSelection &&
            reconnectReason == null &&
            !refreshUrls,
        ohosPlaybackRecovery: reconnectReason != null || refreshUrls,
      );
      if (!_isCurrentPlaybackRequest(requestRevision, loadGeneration) ||
          !_hasActivePlaybackSession) {
        return false;
      }
      final recordedReason = reconnectReason ??
          (playbackUrlRefreshed
              ? LiveReconnectReason.playbackUrlRefresh
              : null);
      if (recordedReason != null) {
        final hostChanged = reconnectHostChanged ??
            didLivePlaybackHostChange(
              previousSource,
              _selectedPlaybackSource,
            );
        if (Utils.isOhos) {
          // 鸿蒙的 initPlaylist 返回时 AVPlayer 还没接受地址，
          // 挂起等原生确认再记账，否则恢复耗时会偏短。
          _armOhosReconnect(
            reason: recordedReason,
            hostChanged: hostChanged,
            startedAt: reconnectStartedAt,
          );
        } else {
          final completedAt = DateTime.now();
          recordLiveLinkHealthEvent(
            LiveLinkEventType.cdnReconnect,
            at: completedAt,
            reconnectReason: recordedReason,
            reconnectHostChanged: hostChanged,
            reconnectRecoveryDuration: reconnectStartedAt == null
                ? null
                : completedAt.difference(reconnectStartedAt),
          );
        }
      }
      return true;
    } catch (e, stackTrace) {
      if (_isCurrentPlaybackRequest(requestRevision, loadGeneration)) {
        _hasActivePlaybackSession = false;
      }
      Log.e("重新打开播放器失败: $e", stackTrace);
      return false;
    }
  }

  bool get _shouldRefreshUrlsOnPlaybackRetry =>
      site.id == Constant.kHuya ||
      site.id == Constant.kDouyu ||
      site.id == Constant.kKuaishou;

  @override
  void mediaEnd() async {
    if (_roomDisposed || _roomSwitching) {
      return;
    }
    final recoveryGeneration = _loadGeneration;
    if (site.id == Constant.kKuaishou) {
      await _runKuaishouRecoverySingleFlight(
        () => _handleMediaEnd(recoveryGeneration),
      );
      return;
    }
    await _handleMediaEnd(recoveryGeneration);
  }

  Future<void> _handleMediaEnd(int recoveryGeneration) async {
    super.mediaEnd();
    if (mediaErrorRetryCount < 2) {
      Log.d("播放结束，尝试第${mediaErrorRetryCount + 1}次恢复");
      if (mediaErrorRetryCount == 1) {
        // 第二次重试前稍等一秒
        await Future.delayed(const Duration(seconds: 1));
        if (!_isCurrentLoad(recoveryGeneration)) {
          return;
        }
      }
      final refreshUrls =
          mediaErrorRetryCount > 0 && _shouldRefreshUrlsOnPlaybackRetry;
      final rotateOhosLine = Utils.isOhos && refreshUrls;
      mediaErrorRetryCount += 1;
      await setPlayer(
        refreshUrls: refreshUrls,
        rotateOhosLine: rotateOhosLine,
        reconnectReason: LiveReconnectReason.mediaEnd,
      );
      return;
    }

    Log.d("播放结束");
    // 依次尝试剩余线路，全部失败后再判定为已下播。
    if (playUrls.length - 1 == currentLineIndex) {
      _hasActivePlaybackSession = false;
      // S2-T1 修复：播放中断后恢复状态轮询，重新以详情确认直播状态
      // （此前稳定播放期取消了轮询，若不恢复则下播/复播都无法被发现）。
      _restartOnlineRefreshTimer();
      if (Utils.isOhos) {
        // AVPlayer completion is not sufficient evidence that a live room is
        // offline. Keep the room active; the independent room-status polling
        // will confirm a real stop after consecutive responses.
        errorMsg.value = "直播流已中断，请稍后重试或切换线路";
        await _tryAutoSwitchToNextLiveRoom(reason: "playback_failure");
        return;
      }
      if (site.id == Constant.kHuya) {
        // 已判定下播或已达重试上限时停止重试，走切房/直播状态确认，
        // 避免主播下播/断流后无限回退重试。重试计数不清零，保证有界。
        if (roomLiveState.value != LiveStatusState.live ||
            mediaErrorRetryCount >= 2) {
          errorMsg.value = "直播流已中断，正在确认直播状态";
          await _tryAutoSwitchToNextLiveRoom(reason: "live_end");
          return;
        }
        // 仍判定直播中且未达重试上限：回退到线路 0 并刷新 URL 重试一次。
        currentLineIndex = 0;
        mediaErrorRetryCount += 1;
        await setPlayer(
          refreshUrls: true,
          reconnectReason: LiveReconnectReason.mediaEnd,
        );
        return;
      }
      errorMsg.value = "直播流已中断，正在确认直播状态";
      await _tryAutoSwitchToNextLiveRoom(reason: "live_end");
    } else {
      await changePlayLine(
        currentLineIndex + 1,
        persist: false,
        reconnectReason: LiveReconnectReason.automaticLineFailover,
      );

      //setPlayer();
    }
  }

  int mediaErrorRetryCount = 0;
  @override
  void mediaError(String error) async {
    if (_roomDisposed || _roomSwitching) {
      return;
    }
    final recoveryGeneration = _loadGeneration;
    if (site.id == Constant.kKuaishou) {
      await _runKuaishouRecoverySingleFlight(
        () => _handleMediaError(error, recoveryGeneration),
      );
      return;
    }
    await _handleMediaError(error, recoveryGeneration);
  }

  Future<void> _handleMediaError(
    String error,
    int recoveryGeneration,
  ) async {
    super.mediaError(error);
    if (mediaErrorRetryCount < 2) {
      Log.d("播放失败，尝试第${mediaErrorRetryCount + 1}次恢复");
      if (mediaErrorRetryCount == 1) {
        // 第二次重试前稍等一秒
        await Future.delayed(const Duration(seconds: 1));
        if (!_isCurrentLoad(recoveryGeneration)) {
          return;
        }
      }
      final refreshUrls =
          mediaErrorRetryCount > 0 && _shouldRefreshUrlsOnPlaybackRetry;
      final rotateOhosLine = Utils.isOhos && refreshUrls;
      mediaErrorRetryCount += 1;
      await setPlayer(
        refreshUrls: refreshUrls,
        rotateOhosLine: rotateOhosLine,
        reconnectReason: LiveReconnectReason.mediaError,
      );
      return;
    }

    if (playUrls.length - 1 == currentLineIndex) {
      _hasActivePlaybackSession = false;
      // S2-T1 修复：播放失败后恢复状态轮询，重新以详情确认直播状态。
      _restartOnlineRefreshTimer();
      if (site.id == Constant.kHuya) {
        // 已判定下播或已达重试上限时停止重试，走切房/播放失败处理，
        // 避免主播下播/断流后无限回退重试。重试计数不清零，保证有界。
        if (roomLiveState.value != LiveStatusState.live ||
            mediaErrorRetryCount >= 2) {
          errorMsg.value = "播放失败";
          SmartDialog.showToast("播放失败: $error");
          await _tryAutoSwitchToNextLiveRoom(reason: "playback_failure");
          return;
        }
        // 仍判定直播中且未达重试上限：回退到线路 0 并刷新 URL 重试一次。
        currentLineIndex = 0;
        mediaErrorRetryCount += 1;
        await setPlayer(
          refreshUrls: true,
          reconnectReason: LiveReconnectReason.mediaError,
        );
        return;
      }
      errorMsg.value = "播放失败";
      SmartDialog.showToast("播放失败: $error");
      await _tryAutoSwitchToNextLiveRoom(reason: "playback_failure");
    } else {
      //currentLineIndex += 1;
      //setPlayer();
      await changePlayLine(
        currentLineIndex + 1,
        persist: false,
        reconnectReason: LiveReconnectReason.automaticLineFailover,
      );
    }
  }

  Future<void> _tryAutoSwitchToNextLiveRoom({required String reason}) async {
    final settings = AppSettingsController.instance;
    final enabled = reason == "live_end"
        ? settings.autoSwitchNextOnLiveEnd.value
        : settings.autoSwitchNextOnPlaybackFailure.value;
    if (!enabled || _autoSwitchingRoom) {
      return;
    }

    final liveChannels = FollowService.instance.sortFollowUsers(
      FollowService.instance.liveList,
    );
    if (liveChannels.isEmpty) {
      return;
    }

    final currentId = "${site.id}_$roomId";
    final currentIndex =
        liveChannels.indexWhere((item) => item.id == currentId);
    final candidates =
        liveChannels.where((item) => item.id != currentId).toList();
    if (candidates.isEmpty) {
      return;
    }

    FollowUser target;
    if (currentIndex < 0 || currentIndex >= liveChannels.length - 1) {
      target = candidates.first;
    } else {
      target = liveChannels[currentIndex + 1];
      if (target.id == currentId) {
        target = candidates.first;
      }
    }

    _autoSwitchingRoom = true;
    try {
      SmartDialog.showToast(
        reason == "live_end" ? "当前直播已结束，已切换到下一个直播间" : "当前直播播放失败，已切换到下一个直播间",
      );
      resetRoom(Sites.allSites[target.siteId]!, target.roomId);
    } finally {
      _autoSwitchingRoom = false;
    }
  }

  /// 读取头条 / SC
  void getSuperChatMessage({bool silent = false}) async {
    if (detail.value == null) {
      return;
    }
    try {
      var sc = await site.liveSite.getSuperChatMessage(
        roomId: detail.value!.roomId,
        detail: detail.value,
      );
      final filtered = sc.map(_sanitizeSuperChatMessage).where((item) {
        if (_isUserShielded(item.userName) || isTempMutedUser(item.userName)) {
          return false;
        }
        return !_isKeywordShielded(_superChatToLiveMessage(item));
      });
      _appendSuperChats(filtered);
      removeSuperChats();
    } catch (e) {
      Log.logPrint(e);
      if (silent) {
        return;
      }
      addSysMsg("SC 读取失败");
    }
  }

  /// 移除已经过期的头条 / SC
  void removeSuperChats() async {
    var now = DateTime.now().millisecondsSinceEpoch;
    superChats.value = superChats
        .where((x) => x.endTime.millisecondsSinceEpoch > now)
        .toList();
    _sortSuperChats();
    _refreshSuperChatFingerprints();
  }

  /// 娣诲姞鍘嗗彶璁板綍
  void addHistory() {
    if (detail.value == null) {
      return;
    }
    var id = "${site.id}_$roomId";
    var history = DBService.instance.getHistory(id);
    if (history != null) {
      history.updateTime = DateTime.now();
    }
    history ??= History(
      id: id,
      roomId: roomId,
      siteId: site.id,
      userName: detail.value?.userName ?? "",
      face: detail.value?.userAvatar ?? "",
      updateTime: DateTime.now(),
    );

    DBService.instance.addOrUpdateHistory(history);
  }

  /// 关注用户
  void followUser() {
    if (detail.value == null) {
      return;
    }
    var id = "${site.id}_$roomId";
    DBService.instance.addFollow(
      FollowUser(
        id: id,
        roomId: roomId,
        siteId: site.id,
        userName: detail.value?.userName ?? "",
        face: detail.value?.userAvatar ?? "",
        addTime: DateTime.now(),
      ),
    );
    followed.value = true;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
  }

  /// 取消关注当前主播
  void removeFollowUser() async {
    if (detail.value == null) {
      return;
    }
    if (!await Utils.showAlertDialog(
      "确定要取消关注这位主播吗？",
      title: "取消关注",
    )) {
      return;
    }

    var id = "${site.id}_$roomId";
    DBService.instance.deleteFollow(id);
    followed.value = false;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
  }

  void share() async {
    if (detail.value == null) {
      return;
    }
    if (Utils.isOhos) {
      try {
        await OhosDocumentService.shareText(
          detail.value!.url,
          title: detail.value!.title,
          isUrl: true,
        );
      } catch (e) {
        Log.logPrint(e);
        SmartDialog.showToast("分享失败：$e");
      }
      return;
    }
    Share.shareUri(Uri.parse(detail.value!.url));
  }

  void copyUrl() {
    if (detail.value == null) {
      return;
    }
    Utils.copyToClipboard(detail.value!.url);
    SmartDialog.showToast("已复制直播间链接");
  }

  /// 复制当前实际播放线路，保持与播放器的线路和 HTTPS 设置一致。
  void copyPlayUrl() {
    if (!liveStatus.value) {
      SmartDialog.showToast("当前直播间未开播");
      return;
    }
    final currentUrl = currentNetworkDiagnosePlaybackUrl;
    if (currentUrl.isEmpty) {
      SmartDialog.showToast("播放地址未就绪");
      return;
    }
    Utils.copyToClipboard(currentUrl);
    SmartDialog.showToast("已复制播放直链");
  }

  /// 底部弹出弹幕设置
  void showDanmuSettingsSheet() {
    Utils.showBottomSheet(
      title: "弹幕设置",
      // 内容注定超过一屏，除了按内容收敛还要留出遮罩可点区域。
      maxHeightFactor: 0.85,
      child: ListView(
        shrinkWrap: true,
        padding: AppStyle.edgeInsetsA12,
        children: [
          DanmuSettingsView(
            danmakuController: danmakuController,
            siteId: site.id,
            previewViewportHeight: danmakuViewportHeight.value,
            onTapDanmuShield: () {
              Get.back();
              showDanmuShield();
            },
          ),
        ],
      ),
    );
  }

  void showLiveSettingsSheet() {
    final settings = AppSettingsController.instance;
    Utils.showBottomSheet(
      title: "播放与网络",
      // 开关很多，内容注定超过一屏，留出遮罩可点区域。
      maxHeightFactor: 0.85,
      child: ListView(
        shrinkWrap: true,
        padding: AppStyle.edgeInsetsA12,
        children: [
          SettingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!Utils.isOhos)
                  Obx(
                    () => SettingsSwitch(
                      title: "硬件解码",
                      subtitle: "播放失败可尝试关闭此选项",
                      value: settings.hardwareDecode.value,
                      onChanged: settings.setHardwareDecode,
                    ),
                  ),
                if (Platform.isAndroid) ...[
                  AppStyle.divider,
                  Obx(
                    () => SettingsSwitch(
                      title: "兼容模式",
                      subtitle: "若播放卡顿可尝试打开此选项",
                      value: settings.playerCompatMode.value,
                      onChanged: settings.setPlayerCompatMode,
                    ),
                  ),
                ],
                if (!Utils.isOhos) AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "后台播放",
                    subtitle: "移动端仍可能被系统省电策略关闭",
                    value: settings.allowBackgroundPlayback.value,
                    onChanged: settings.setAllowBackgroundPlayback,
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "强制 HTTPS",
                    subtitle: "将 http 播放链接替换为 https",
                    value: settings.playerForceHttps.value,
                    onChanged: settings.setPlayerForceHttps,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void showVolumeSlider(
    BuildContext targetContext, {
    bool keepAlive = false,
  }) {
    hidevolumeTimer?.cancel();
    pauseControlsAutoHide();
    SmartDialog.showAttach(
      targetContext: targetContext,
      alignment: Alignment.topCenter,
      displayTime: keepAlive ? null : const Duration(seconds: 4),
      maskColor: const Color(0x00000000),
      tag: volumeSliderDialogTag,
      keepSingle: true,
      onDismiss: resumeControlsAutoHide,
      builder: (context) {
        return MouseRegion(
          onEnter: (_) => hidevolumeTimer?.cancel(),
          onExit: (_) => hideVolumeSlider(),
          child: Obx(
            () => ImmersiveVolumeSlider(
              value: AppSettingsController.instance.playerVolume.value,
              onChanged: (newValue) {
                setSessionPlayerVolume(newValue, persist: true);
              },
              onMute: () {
                unawaited(toggleMute());
                hideVolumeSlider();
              },
            ),
          ),
        );
      },
    );
  }

  void hideVolumeSlider() {
    hidevolumeTimer?.cancel();
    hidevolumeTimer = Timer(const Duration(milliseconds: 220), () {
      SmartDialog.dismiss(tag: volumeSliderDialogTag);
    });
  }

  void showQualitySheet() {
    Utils.showBottomSheet(
      title: "切换清晰度",
      child: RadioGroup<int>(
        groupValue: qualityLocked.value ? currentQuality : -1,
        onChanged: (v) {
          Get.back();
          if (v == -1) {
            unawaited(useAutomaticQuality());
          } else {
            markQualitySelectionAsManual();
            qualityLocked.value = true;
            currentQuality = v ?? 0;
            currentQualityInfo.value = qualites[currentQuality].quality;
            saveQualityMemory();
            getPlayUrl(userInitiatedQualityChange: true);
          }
        },
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: qualites.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              return const RadioListTile(
                value: -1,
                title: Text("自动"),
                subtitle: Text("根据网络与设备情况自动调整"),
              );
            }
            var item = qualites[i - 1];
            return RadioListTile(
              value: i - 1,
              title: Text(item.quality),
            );
          },
        ),
      ),
    );
  }

  void showPlayUrlsSheet() {
    Utils.showBottomSheet(
      title: "线路选择",
      child: RadioGroup<int>(
        groupValue: currentLineIndex,
        onChanged: (v) {
          Get.back();
          changePlayLine(v ?? 0);
        },
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: playUrls.length,
          itemBuilder: (_, i) {
            return RadioListTile(
              value: i,
              title: Text(lineDisplayName(i)),
            );
          },
        ),
      ),
    );
  }

  void showPlayerSettingsSheet() {
    Utils.showBottomSheet(
      title: "画面尺寸",
      child: Obx(
        () => RadioGroup<int>(
          groupValue: AppSettingsController.instance.scaleMode.value,
          onChanged: _onScaleModeChanged,
          child: ListView(
            shrinkWrap: true,
            padding: AppStyle.edgeInsetsV12,
            children: const [
              RadioListTile(
                value: 0,
                title: Text("适应"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 1,
                title: Text("拉伸"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 2,
                title: Text("铺满"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 3,
                title: Text("16:9"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 4,
                title: Text("4:3"),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onScaleModeChanged(int? value) {
    AppSettingsController.instance.setScaleMode(value ?? 0);
    updateScaleMode();
  }

  void showDanmuShield() {
    Get.toNamed(RoutePath.kSettingsDanmuShield);
  }

  LiveSubCategory? _buildRecommendationCategory() {
    final roomDetail = detail.value;
    if (roomDetail == null) {
      return null;
    }
    final categoryId = (roomDetail.categoryId ?? "").trim();
    final categoryName = (roomDetail.categoryName ?? "").trim();
    final parentId = (roomDetail.categoryParentId ?? "").trim();
    final parentName = (roomDetail.categoryParentName ?? "").trim();
    if (categoryId.isEmpty && parentId.isEmpty) {
      return null;
    }
    final resolvedId = categoryId.isNotEmpty ? categoryId : parentId;
    final resolvedParentId = parentId.isNotEmpty ? parentId : resolvedId;
    final resolvedName = categoryName.isNotEmpty
        ? categoryName
        : parentName.isNotEmpty
            ? parentName
            : roomDetail.title.trim();
    if (resolvedId.isEmpty || resolvedName.isEmpty) {
      return null;
    }
    final pic = roomDetail.categoryPic?.trim();
    return LiveSubCategory(
      id: resolvedId,
      name: resolvedName,
      parentId: resolvedParentId,
      pic: pic == null || pic.isEmpty ? null : pic,
    );
  }

  bool get hasCategoryRecommendation => _buildRecommendationCategory() != null;

  String get currentRecommendationSubtitle {
    final roomDetail = detail.value;
    final category = _buildRecommendationCategory();
    if (roomDetail == null || category == null) {
      return "当前直播间暂时还没有可用的分区标签";
    }
    final parentName = (roomDetail.categoryParentName ?? "").trim();
    if (parentName.isNotEmpty && parentName != category.name) {
      return "${site.name} / $parentName / ${category.name}";
    }
    return "${site.name} / ${category.name}";
  }

  bool get useFullscreenSidePanelMenus =>
      fullScreenState.value &&
      (Platform.isAndroid || Platform.isIOS || Utils.isOhos);

  List<String> get enabledQuickAccessKeys {
    final settings = AppSettingsController.instance;
    return settings.liveRoomQuickAccessSort
        .where((key) =>
            settings.liveRoomQuickAccessEnabled.contains(key) &&
            Constant.allLiveRoomQuickAccess.containsKey(key) &&
            (key != "contribution_rank" ||
                (supportsContributionRank &&
                    settings.contributionRankEnable.value)))
        .toList();
  }

  String quickAccessTitle(String key) {
    if (key == "contribution_rank") {
      return site.id == Constant.kDouyu ? "亲密榜" : "贡献榜";
    }
    return Constant.allLiveRoomQuickAccess[key]?.title ?? "";
  }

  String quickAccessSubtitle(String key) {
    if (key == "recommendation") {
      return currentRecommendationSubtitle;
    }
    if (key == "contribution_rank") {
      if (!supportsContributionRank) {
        return "当前平台暂无贡献榜";
      }
      return site.id == Constant.kDouyu ? "打开当前直播间亲密榜" : "打开当前直播间贡献榜";
    }
    return Constant.allLiveRoomQuickAccess[key]?.subtitle ?? "";
  }

  void showContributionRankSheet() {
    if (!supportsContributionRank) {
      return;
    }
    if (!AppSettingsController.instance.contributionRankEnable.value) {
      return;
    }
    fetchContributionRank(forceRefresh: true);
    Utils.showBottomSheet(
      title: site.id == Constant.kDouyu ? "亲密榜" : "贡献榜",
      child: SizedBox(
        height: Get.height * 0.75,
        child: LiveContributionRankPanel(controller: this),
      ),
    );
  }

  Widget buildHistorySelection({
    required VoidCallback onClose,
    ScrollController? scrollController,
    void Function(History item, Site site)? onSelected,
  }) {
    final currentSite = site;
    final histories = <History>[].obs;
    final loading = true.obs;

    Future<void> loadHistory() async {
      loading.value = true;
      try {
        histories.value = DBService.instance.getHistores();
      } finally {
        loading.value = false;
      }
    }

    unawaited(loadHistory());

    return Obx(() {
      if (loading.value && histories.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (histories.isEmpty) {
        return AppEmptyWidget(
          message: "暂无观看历史",
          onRefresh: loadHistory,
        );
      }
      return RefreshIndicator(
        onRefresh: loadHistory,
        child: ListView.separated(
          key: const PageStorageKey<String>("liveRoomHistorySelection"),
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppStyle.edgeInsetsA12,
          itemCount: histories.length,
          separatorBuilder: (_, __) => AppStyle.divider,
          itemBuilder: (_, i) {
            final item = histories[i];
            final historySite = Sites.allSites[item.siteId];
            final isCurrent =
                currentSite.id == item.siteId && roomId == item.roomId;
            return Material(
              color: Colors.transparent,
              child: ListTile(
                selected: isCurrent,
                contentPadding: AppStyle.edgeInsetsL16.copyWith(right: 8),
                leading: NetImage(
                  item.face,
                  width: 48,
                  height: 48,
                  borderRadius: 24,
                ),
                title: Text(
                  item.userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Row(
                  children: [
                    if (historySite != null) ...[
                      Image.asset(
                        historySite.logo,
                        width: 20,
                      ),
                      AppStyle.hGap4,
                    ],
                    Expanded(
                      child: Text(
                        historySite?.name ?? item.siteId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    AppStyle.hGap8,
                    Text(
                      Utils.parseTime(item.updateTime),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                onTap: historySite == null || (isCurrent && onSelected != null)
                    ? null
                    : () {
                        onClose();
                        if (onSelected != null) {
                          onSelected(item, historySite);
                        } else {
                          resetRoom(historySite, item.roomId);
                        }
                      },
                onLongPress: () async {
                  final confirmed = await Utils.showAlertDialog(
                    "确定要删除此记录吗?",
                    title: "删除记录",
                  );
                  if (!confirmed) {
                    return;
                  }
                  await DBService.instance.historyBox.delete(item.id);
                  await loadHistory();
                },
              ),
            );
          },
        ),
      );
    });
  }

  Widget buildCategoryRecommendationSelection({
    required VoidCallback onClose,
    ScrollController? scrollController,
  }) {
    final currentSite = site;
    final currentRoomId = roomId;
    final category = _buildRecommendationCategory();
    if (category == null) {
      return const AppEmptyWidget(
        message: "当前直播间暂无同类推荐内容",
      );
    }

    final rooms = <LiveRoomItem>[].obs;
    final loading = true.obs;
    final page = 1.obs;
    final hasMore = true.obs;

    Future<void> loadRecommendations({bool refresh = false}) async {
      if (loading.value && !refresh) {
        return;
      }
      loading.value = true;
      try {
        final targetPage = refresh ? 1 : page.value;
        final result = await site.liveSite.getCategoryRooms(
          category,
          page: targetPage,
        );
        final fetched =
            result.items.where((item) => item.roomId != roomId).toList();
        if (refresh) {
          rooms.assignAll(fetched);
          page.value = 2;
        } else {
          final existingRoomIds = rooms.map((item) => item.roomId).toSet();
          rooms.addAll(
            fetched.where((item) => !existingRoomIds.contains(item.roomId)),
          );
          page.value = targetPage + 1;
        }
        hasMore.value = fetched.isNotEmpty;
      } catch (e) {
        if (rooms.isEmpty) {
          SmartDialog.showToast("加载同类推荐失败: ${exceptionToString(e)}");
        } else {
          handleError(e);
        }
      } finally {
        loading.value = false;
      }
    }

    unawaited(loadRecommendations(refresh: true));

    return Obx(() {
      if (loading.value && rooms.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (rooms.isEmpty) {
        return AppEmptyWidget(
          message: "当前分区暂无可用推荐",
          onRefresh: () => loadRecommendations(refresh: true),
        );
      }
      return RefreshIndicator(
        onRefresh: () => loadRecommendations(refresh: true),
        child: ListView.builder(
          key: const PageStorageKey<String>(
            "liveRoomCategoryRecommendationSelection",
          ),
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppStyle.edgeInsetsA12,
          itemCount: rooms.length + 2,
          itemBuilder: (_, i) {
            if (i == 0) {
              return Padding(
                padding: AppStyle.edgeInsetsB12,
                child: Text(
                  currentRecommendationSubtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              );
            }
            if (i == rooms.length + 1) {
              if (loading.value) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (!hasMore.value) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      "已经到底了",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: TextButton.icon(
                  onPressed: () => loadRecommendations(),
                  icon: const Icon(Icons.expand_more),
                  label: const Text("加载更多"),
                ),
              );
            }

            final item = rooms[i - 1];
            final isCurrent =
                currentSite.id == site.id && currentRoomId == item.roomId;
            return Padding(
              padding: EdgeInsets.only(bottom: i == rooms.length ? 0 : 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    onClose();
                    resetRoom(site, item.roomId);
                  },
                  child: Ink(
                    padding: AppStyle.edgeInsetsA8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: isCurrent
                          ? Get.theme.colorScheme.primary.withAlpha(25)
                          : Get.theme.cardColor,
                      border: Border.all(
                        color: isCurrent
                            ? Get.theme.colorScheme.primary.withAlpha(120)
                            : Colors.grey.withAlpha(25),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: NetImage(
                            item.cover,
                            width: 108,
                            height: 60,
                            fit: BoxFit.cover,
                          ),
                        ),
                        AppStyle.hGap12,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              AppStyle.vGap4,
                              Text(
                                item.userName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              AppStyle.vGap4,
                              Text(
                                "热度 ${Utils.onlineToString(item.online)}",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    });
  }

  void openHistoryPage() {
    if (useFullscreenSidePanelMenus) {
      Utils.showRightDialog(
        title: "观看历史",
        width: 420,
        useSystem: false,
        child: buildHistorySelection(
          onClose: Utils.hideRightDialog,
          scrollController: liveRoomHistoryScrollController,
        ),
      );
      return;
    }
    AppNavigator.toHistory(
      onRoomSelected: (selectedSite, selectedRoomId) {
        resetRoom(selectedSite, selectedRoomId);
      },
    );
  }

  void openCategoryRecommendation() {
    final category = _buildRecommendationCategory();
    if (category == null) {
      SmartDialog.showToast("当前直播间还没有可用的分区标签");
      return;
    }
    if (useFullscreenSidePanelMenus) {
      Utils.showRightDialog(
        title: "同类推荐",
        width: 420,
        useSystem: false,
        child: buildCategoryRecommendationSelection(
          onClose: Utils.hideRightDialog,
          scrollController: liveRoomRecommendationScrollController,
        ),
      );
      return;
    }
    AppNavigator.toCategoryDetail(
      site: site,
      category: category,
      excludedRoomId: roomId,
      onRoomSelected: (selectedSite, selectedRoomId) {
        resetRoom(selectedSite, selectedRoomId);
      },
    );
  }

  void startFollowHoldPreview(FollowUser follow) {
    if (Utils.isOhos) {
      SmartDialog.showToast("鸿蒙版暂不支持长按预览");
      return;
    }
    if (Platform.isIOS && !_holdPreviewEnabledOnIos) {
      SmartDialog.showToast("当前 iOS 版本暂未开放长按预览");
      return;
    }
    if (follow.liveStatus.value != 2) {
      SmartDialog.showToast("主播未开播，无法预览");
      return;
    }
    final targetSite = Sites.allSites[follow.siteId];
    if (targetSite == null) {
      SmartDialog.showToast("当前平台暂不支持预览");
      return;
    }
    final target = MultiRoomItem.fromFollow(follow);
    if (target.key == "${site.id}_$roomId" || _roomDisposed) {
      return;
    }
    final mainShouldPlay = player.state.playing || player.state.buffering;
    _holdPreviewMainWasPlaying = mainShouldPlay;

    final revision = ++_holdPreviewRevision;
    _holdPreviewLingerTimer?.cancel();
    _holdPreviewLingerTimer = null;
    _holdPreviewLingerDeadline = null;
    _holdPreviewPhase = LiveRoomHoldPreviewPhase.holding;
    _holdPreviewItem = target;
    _removeHoldPreviewOverlay();
    _insertHoldPreviewOverlay();
    _markHoldPreviewOverlayNeedsBuild();

    unawaited(
      _holdPreviewMutations.run(() async {
        await _restoreHoldPreviewMainAudioLocked();
        await _disposeHoldPreviewPlayerLocked();
        if (!_isCurrentHoldPreview(revision, target.key)) return;
        await _createHoldPreviewPlayerLocked(
          item: target,
          revision: revision,
          allowAudio: true,
          mainShouldPlay: mainShouldPlay,
        );
      }).catchError((Object error, StackTrace stackTrace) {
        Log.e("创建长按预览失败: $error", stackTrace);
        if (_isCurrentHoldPreview(revision, target.key)) {
          unawaited(closeFollowHoldPreview());
        }
      }),
    );
  }

  void endFollowHoldPreview() {
    if (_holdPreviewPhase != LiveRoomHoldPreviewPhase.holding) return;
    _holdPreviewPhase = LiveRoomHoldPreviewPhase.lingering;
    _startHoldPreviewLingerTimer(_holdPreviewRevision);
    _markHoldPreviewOverlayNeedsBuild();
  }

  void cancelFollowHoldPreview() {
    if (_holdPreviewPhase == LiveRoomHoldPreviewPhase.closed) return;
    unawaited(closeFollowHoldPreview());
  }

  Future<void> closeFollowHoldPreview() async {
    if (_holdPreviewClosing &&
        _holdPreviewPhase == LiveRoomHoldPreviewPhase.closed) {
      await _holdPreviewMutations.idle;
      return;
    }
    _holdPreviewClosing = true;
    _holdPreviewRevision += 1;
    _holdPreviewLingerTimer?.cancel();
    _holdPreviewLingerTimer = null;
    _holdPreviewLingerDeadline = null;
    _holdPreviewPhase = LiveRoomHoldPreviewPhase.closed;
    _holdPreviewItem = null;
    _removeHoldPreviewOverlay();
    try {
      await _holdPreviewMutations.run(() async {
        await _restoreHoldPreviewMainAudioLocked();
        await _disposeHoldPreviewPlayerLocked();
      });
    } catch (error, stackTrace) {
      Log.e("关闭长按预览失败: $error", stackTrace);
    } finally {
      _holdPreviewClosing = false;
    }
  }

  bool _isCurrentHoldPreview(int revision, String roomKey) {
    return !_roomDisposed &&
        revision == _holdPreviewRevision &&
        _holdPreviewPhase != LiveRoomHoldPreviewPhase.closed &&
        _holdPreviewItem?.key == roomKey;
  }

  void _insertHoldPreviewOverlay() {
    final item = _holdPreviewItem;
    if (item == null || _holdPreviewOverlay != null) return;
    final context = Get.context;
    if (context == null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _holdPreviewOverlay = OverlayEntry(
      builder: (overlayContext) {
        final activeItem = _holdPreviewItem;
        if (activeItem == null ||
            _holdPreviewPhase == LiveRoomHoldPreviewPhase.closed) {
          return const SizedBox.shrink();
        }
        final mediaQuery = MediaQuery.of(overlayContext);
        final renderObject = globalPlayerKey.currentContext?.findRenderObject();
        Rect playerRect;
        if (renderObject is RenderBox && renderObject.hasSize) {
          playerRect =
              renderObject.localToGlobal(Offset.zero) & renderObject.size;
        } else {
          playerRect = Offset.zero & mediaQuery.size;
        }
        final portrait = mediaQuery.orientation == Orientation.portrait &&
            !fullScreenState.value;
        final obscuredRight = !useBottomSheetPlayerMenus
            ? Utils.activeRightDialogPanelWidth(mediaQuery.size)
            : 0.0;
        final rect = resolveLiveRoomHoldPreviewRect(
          screenSize: mediaQuery.size,
          safePadding: mediaQuery.viewPadding,
          playerRect: playerRect,
          portrait: portrait,
          obscuredRight: obscuredRight,
        );
        return LiveRoomHoldPreviewOverlay(
          rect: rect,
          item: activeItem,
          phase: _holdPreviewPhase,
          playerController: _holdPreviewPlayer?.item.key == activeItem.key
              ? _holdPreviewPlayer
              : null,
          lingerDeadline: _holdPreviewLingerDeadline,
          onTap: _promoteHoldPreview,
          onPhysicalSizeChanged: (width, height) {
            if (_holdPreviewPhase == LiveRoomHoldPreviewPhase.switching ||
                _holdPreviewPhase == LiveRoomHoldPreviewPhase.closed) {
              return;
            }
            final preview = _holdPreviewPlayer;
            if (preview == null || preview.item.key != activeItem.key) return;
            // The preview controller applies this only on iOS. Keeping the
            // call here lets rotation and split-view resize the texture to the
            // actual overlay instead of allocating an original-quality frame.
            preview.updatePreviewOutputSize(width, height);
          },
        );
      },
    );
    overlay.insert(_holdPreviewOverlay!);
  }

  void _removeHoldPreviewOverlay() {
    final overlay = _holdPreviewOverlay;
    _holdPreviewOverlay = null;
    overlay?.remove();
    overlay?.dispose();
  }

  void _markHoldPreviewOverlayNeedsBuild() {
    _holdPreviewOverlay?.markNeedsBuild();
  }

  void _startHoldPreviewLingerTimer(int revision) {
    _holdPreviewLingerTimer?.cancel();
    final deadline = DateTime.now().add(_holdPreviewLingerDuration);
    _holdPreviewLingerDeadline = deadline;
    _holdPreviewLingerTimer = Timer(_holdPreviewLingerDuration, () {
      if (revision != _holdPreviewRevision ||
          _holdPreviewPhase != LiveRoomHoldPreviewPhase.lingering) {
        return;
      }
      unawaited(closeFollowHoldPreview());
    });
  }

  Future<void> _createHoldPreviewPlayerLocked({
    required MultiRoomItem item,
    required int revision,
    required bool allowAudio,
    required bool mainShouldPlay,
  }) async {
    if (!_isCurrentHoldPreview(revision, item.key)) return;
    final expectedMainMuted = mutedState.value;
    final expectedMainVolume = player.state.volume.clamp(0, 100).toDouble();
    final tag = "live-room-hold-preview-${identityHashCode(this)}-$revision";
    var loadCancelled = false;
    final preview = Get.put(
      MultiRoomPlayerController(
        item,
        initialShowDanmaku: false,
        lightweightPreview: true,
        externalCancellation: () =>
            loadCancelled || !_isCurrentHoldPreview(revision, item.key),
      ),
      tag: tag,
    );
    _holdPreviewPlayer = preview;
    _holdPreviewPlayerTag = tag;
    _markHoldPreviewOverlayNeedsBuild();

    final loadTimeoutTimer = Timer(_holdPreviewLoadTimeout, () {
      loadCancelled = true;
      if (!_isCurrentHoldPreview(revision, item.key)) return;
      preview.errorText.value = "预览加载超时";
      _markHoldPreviewOverlayNeedsBuild();
      if (_holdPreviewPhase == LiveRoomHoldPreviewPhase.loadingPrevious) {
        _holdPreviewRevision += 1;
        _holdPreviewPhase = LiveRoomHoldPreviewPhase.closed;
        _holdPreviewItem = null;
        _removeHoldPreviewOverlay();
      }
    });
    try {
      await preview.load();
    } finally {
      loadTimeoutTimer.cancel();
    }
    if (loadCancelled) return;
    if (!_isCurrentHoldPreview(revision, item.key) ||
        preview.errorText.value.isNotEmpty ||
        !preview.liveStatus.value) {
      if (_isCurrentHoldPreview(revision, item.key)) {
        await _stabilizeMainAfterMutedPreviewOpenLocked(
          preview: preview,
          revision: revision,
          mainShouldPlay: mainShouldPlay,
          expectedMainMuted: expectedMainMuted,
          expectedMainVolume: expectedMainVolume,
        );
      }
      return;
    }
    final advancing = await preview.waitUntilActuallyPlaying(
      const Duration(seconds: 3),
    );
    if (!advancing || !_isCurrentHoldPreview(revision, item.key)) {
      if (_isCurrentHoldPreview(revision, item.key)) {
        preview.errorText.value = "预览起播超时";
        _markHoldPreviewOverlayNeedsBuild();
        await _stabilizeMainAfterMutedPreviewOpenLocked(
          preview: preview,
          revision: revision,
          mainShouldPlay: mainShouldPlay,
          expectedMainMuted: expectedMainMuted,
          expectedMainVolume: expectedMainVolume,
        );
      }
      return;
    }

    if (Platform.isIOS) {
      await _recoverHoldPreviewPlayers(
        preview: preview,
        revision: revision,
        mainShouldPlay: mainShouldPlay,
      );
    }
    if (allowAudio &&
        AppSettingsController.instance.liveRoomHoldPreviewAudio.value &&
        _isCurrentHoldPreview(revision, item.key)) {
      await _giveAudioToHoldPreviewLocked(
        preview,
        revision: revision,
        roomKey: item.key,
      );
    } else if (_isCurrentHoldPreview(revision, item.key)) {
      await _stabilizeMainAfterMutedPreviewOpenLocked(
        preview: preview,
        revision: revision,
        mainShouldPlay: mainShouldPlay,
        expectedMainMuted: expectedMainMuted,
        expectedMainVolume: expectedMainVolume,
      );
    }
  }

  Future<void> _stabilizeMainAfterMutedPreviewOpenLocked({
    required MultiRoomPlayerController preview,
    required int revision,
    required bool mainShouldPlay,
    required bool expectedMainMuted,
    required double expectedMainVolume,
  }) async {
    // A muted Player.open may still take iOS' shared audio session. Reapply
    // the main room's exact session state, then verify both timelines once
    // more because that audio-session activation can interrupt the preview.
    await setSessionPlayerVolume(
      expectedMainMuted ? 0 : expectedMainVolume,
    );
    if (Platform.isIOS) {
      await _recoverHoldPreviewPlayers(
        preview: preview,
        revision: revision,
        mainShouldPlay: mainShouldPlay,
      );
    }
  }

  Future<bool> _recoverHoldPreviewPlayers({
    required MultiRoomPlayerController preview,
    required int revision,
    required bool mainShouldPlay,
  }) async {
    await preview.playerMutationsIdle;
    final targetKey = _holdPreviewItem?.key;
    return _holdPreviewRecovery.recover(
      targets: [
        MultiRoomPlaybackRecoveryTarget(
          roomKey: "main:${site.id}/$roomId",
          shouldPlay: () =>
              mainShouldPlay &&
              !_roomDisposed &&
              !isBackground &&
              revision == _holdPreviewRevision,
          requestPlay: (forceRestart) async {
            if (forceRestart) {
              await player.pause();
            }
            await player.play();
          },
          waitUntilPlaying: _waitUntilMainPlayerAdvances,
        ),
        MultiRoomPlaybackRecoveryTarget(
          roomKey: "preview:${preview.item.key}",
          shouldPlay: () =>
              revision == _holdPreviewRevision &&
              targetKey == _holdPreviewItem?.key &&
              preview.shouldRecoverPlayback,
          requestPlay: preview.ensurePlaying,
          waitUntilPlaying: preview.waitUntilActuallyPlaying,
        ),
      ],
      isCancelled: () =>
          _roomDisposed ||
          isBackground ||
          revision != _holdPreviewRevision ||
          targetKey != _holdPreviewItem?.key,
    );
  }

  Future<bool> _waitUntilMainPlayerAdvances(Duration timeout) async {
    if (_roomDisposed || isBackground) return false;
    final initial = player.state.position;
    StreamSubscription<Duration>? subscription;
    final completer = Completer<bool>();
    try {
      subscription = player.stream.position.listen(
        (position) {
          if (_roomDisposed || isBackground) {
            if (!completer.isCompleted) completer.complete(false);
            return;
          }
          if ((position - initial).inMilliseconds.abs() >= 20 &&
              !completer.isCompleted) {
            completer.complete(true);
          }
        },
        onError: (Object _, StackTrace __) {
          if (!completer.isCompleted) completer.complete(false);
        },
      );
      return await completer.future.timeout(
        timeout,
        onTimeout: () => false,
      );
    } finally {
      await subscription?.cancel();
    }
  }

  Future<void> _giveAudioToHoldPreviewLocked(
    MultiRoomPlayerController preview, {
    required int revision,
    required String roomKey,
  }) async {
    if (_holdPreviewOwnsAudio || !_isCurrentHoldPreview(revision, roomKey)) {
      return;
    }
    _holdPreviewAudioSnapshot = _HoldPreviewAudioSnapshot(
      volume: player.state.volume.clamp(0, 100).toDouble(),
      muted: mutedState.value,
    );
    _holdPreviewOwnsAudio = true;
    await setSessionPlayerVolume(0);
    if (!_isCurrentHoldPreview(revision, roomKey)) {
      await _restoreHoldPreviewMainAudioLocked();
      return;
    }
    final snapshot = _holdPreviewAudioSnapshot!;
    final desired = snapshot.muted
        ? AppSettingsController.instance.playerVolume.value
        : snapshot.volume;
    await preview.setVolume(desired);
    if (!_isCurrentHoldPreview(revision, roomKey)) {
      await _restoreHoldPreviewMainAudioLocked();
      return;
    }
    await preview.setMuted(false);
    if (!_isCurrentHoldPreview(revision, roomKey)) {
      await _restoreHoldPreviewMainAudioLocked();
      return;
    }
    if (Platform.isIOS &&
        !await preview.waitUntilActuallyPlaying(
          const Duration(milliseconds: 700),
        )) {
      await _restoreHoldPreviewMainAudioLocked();
      throw StateError("预览播放器接管声音后停止推进");
    }
  }

  Future<void> _restoreHoldPreviewMainAudioLocked() async {
    if (!_holdPreviewOwnsAudio) {
      _holdPreviewAudioSnapshot = null;
      return;
    }
    final preview = _holdPreviewPlayer;
    if (preview != null) {
      await preview.setMuted(true);
    }
    final snapshot = _holdPreviewAudioSnapshot;
    _holdPreviewOwnsAudio = false;
    _holdPreviewAudioSnapshot = null;
    if (snapshot != null && !_roomDisposed && !isPlayerClosing) {
      await setSessionPlayerVolume(snapshot.muted ? 0 : snapshot.volume);
    }
  }

  Future<void> _disposeHoldPreviewPlayerLocked() async {
    final preview = _holdPreviewPlayer;
    final tag = _holdPreviewPlayerTag;
    _holdPreviewPlayer = null;
    _holdPreviewPlayerTag = null;
    if (preview == null) return;
    final expectedMainMuted = mutedState.value;
    final expectedMainVolume = player.state.volume.clamp(0, 100).toDouble();
    await WidgetsBinding.instance.endOfFrame;
    try {
      await preview.disposePreviewPlayer();
    } finally {
      if (tag != null &&
          Get.isRegistered<MultiRoomPlayerController>(tag: tag)) {
        await Get.delete<MultiRoomPlayerController>(tag: tag, force: true);
      }
    }
    if (!_roomDisposed && !isPlayerClosing) {
      await setSessionPlayerVolume(
        expectedMainMuted ? 0 : expectedMainVolume,
      );
    }
    await _recoverMainAfterHoldPreviewMutationLocked();
  }

  Future<void> _recoverMainAfterHoldPreviewMutationLocked() async {
    if (!Platform.isIOS ||
        !_holdPreviewMainWasPlaying ||
        _roomDisposed ||
        isBackground ||
        isPlayerClosing) {
      return;
    }
    await _holdPreviewRecovery.recover(
      targets: [
        MultiRoomPlaybackRecoveryTarget(
          roomKey: "main:${site.id}/$roomId",
          shouldPlay: () =>
              !_roomDisposed &&
              !isBackground &&
              !isPlayerClosing &&
              _holdPreviewMainWasPlaying,
          requestPlay: (forceRestart) async {
            if (forceRestart) {
              await player.pause();
            }
            await player.play();
          },
          waitUntilPlaying: _waitUntilMainPlayerAdvances,
        ),
      ],
      isCancelled: () => _roomDisposed || isBackground || isPlayerClosing,
    );
  }

  void _promoteHoldPreview() {
    if (_holdPreviewPhase != LiveRoomHoldPreviewPhase.lingering ||
        _holdPreviewPlayer == null ||
        _holdPreviewItem == null) {
      return;
    }
    final revision = ++_holdPreviewRevision;
    final target = _holdPreviewItem!;
    final previous = MultiRoomItem(
      site: site,
      roomId: roomId,
      userName: detail.value?.userName ?? "",
      face: detail.value?.userAvatar ?? "",
    );
    _holdPreviewLingerTimer?.cancel();
    _holdPreviewLingerTimer = null;
    _holdPreviewLingerDeadline = null;
    _holdPreviewPhase = LiveRoomHoldPreviewPhase.switching;
    _markHoldPreviewOverlayNeedsBuild();

    unawaited(
      _holdPreviewMutations.run(() async {
        final targetPreview = _holdPreviewPlayer;
        if (targetPreview == null ||
            !_isCurrentHoldPreview(revision, target.key)) {
          return;
        }
        await targetPreview.playerMutationsIdle;
        if (!_isCurrentHoldPreview(revision, target.key)) return;
        bool switched;
        _holdPreviewPromotingMain = true;
        try {
          await resetRoom(
            target.site,
            target.roomId,
            fromHoldPreview: true,
          );
          if (_holdPreviewOwnsAudio) {
            // resetRoom restores persisted intent before the target stream opens.
            // Keep the main player silent until the preview-to-main handoff is
            // verified, preventing a short double-audio window.
            await setSessionPlayerVolume(0);
          }
          switched = await _waitForTargetRoomPlayback(
            target,
            revision: revision,
          );
        } finally {
          _holdPreviewPromotingMain = false;
        }
        if (!switched || !_isCurrentHoldPreview(revision, target.key)) {
          await _restoreHoldPreviewMainAudioLocked();
          await _disposeHoldPreviewPlayerLocked();
          _removeHoldPreviewOverlay();
          _holdPreviewPhase = LiveRoomHoldPreviewPhase.closed;
          _holdPreviewItem = null;
          if (!_roomDisposed && "${site.id}_$roomId" != previous.key) {
            await resetRoom(
              previous.site,
              previous.roomId,
              fromHoldPreview: true,
            );
          }
          SmartDialog.showToast("切换直播间失败，已返回原直播间");
          return;
        }

        _holdPreviewMainWasPlaying = true;
        await _restoreHoldPreviewMainAudioLocked();
        _holdPreviewPhase = LiveRoomHoldPreviewPhase.loadingPrevious;
        _holdPreviewItem = previous;
        _removeHoldPreviewOverlay();
        _insertHoldPreviewOverlay();
        _markHoldPreviewOverlayNeedsBuild();
        await _disposeHoldPreviewPlayerLocked();
        if (!_isCurrentHoldPreview(revision, previous.key)) return;

        await _createHoldPreviewPlayerLocked(
          item: previous,
          revision: revision,
          allowAudio: false,
          mainShouldPlay: true,
        );
        final previousPreview = _holdPreviewPlayer;
        if (!_isCurrentHoldPreview(revision, previous.key) ||
            previousPreview == null ||
            previousPreview.errorText.value.isNotEmpty ||
            !previousPreview.liveStatus.value) {
          _removeHoldPreviewOverlay();
          _holdPreviewPhase = LiveRoomHoldPreviewPhase.closed;
          _holdPreviewItem = null;
          await _disposeHoldPreviewPlayerLocked();
          return;
        }
        _holdPreviewPhase = LiveRoomHoldPreviewPhase.lingering;
        _startHoldPreviewLingerTimer(revision);
        _markHoldPreviewOverlayNeedsBuild();
      }).catchError((Object error, StackTrace stackTrace) {
        Log.e("预览切台失败: $error", stackTrace);
        unawaited(closeFollowHoldPreview());
      }),
    );
  }

  Future<bool> _waitForTargetRoomPlayback(
    MultiRoomItem target, {
    required int revision,
  }) async {
    Duration? baseline;
    StreamSubscription<Duration>? subscription;
    Timer? stateTimer;
    final completer = Completer<bool>();
    bool stillCurrent() =>
        !_roomDisposed &&
        revision == _holdPreviewRevision &&
        "${site.id}_$roomId" == target.key;
    try {
      subscription = player.stream.position.listen(
        (position) {
          if (!stillCurrent()) {
            if (!completer.isCompleted) completer.complete(false);
            return;
          }
          if (!player.state.playing || !liveStatus.value) return;
          final first = baseline;
          if (first == null) {
            baseline = position;
            return;
          }
          if ((position - first).inMilliseconds.abs() >= 20 &&
              !completer.isCompleted) {
            completer.complete(true);
          }
        },
        onError: (Object _, StackTrace __) {
          if (!completer.isCompleted) completer.complete(false);
        },
      );
      stateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!stillCurrent() || loadError.value) {
          if (!completer.isCompleted) completer.complete(false);
        } else if (detail.value != null &&
            roomLiveState.value == LiveStatusState.offline) {
          if (!completer.isCompleted) completer.complete(false);
        }
      });
      return await completer.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => false,
      );
    } finally {
      stateTimer?.cancel();
      await subscription?.cancel();
    }
  }

  List<FollowUser> _followUsersByFilterMode(int filterMode) {
    switch (filterMode) {
      case 1:
        return FollowService.instance.sortFollowUsers(
          FollowService.instance.liveList,
        );
      case 2:
        return FollowService.instance.sortFollowUsers(
          FollowService.instance.notLiveList,
        );
      default:
        return FollowService.instance.sortFollowUsers(
          FollowService.instance.followList,
        );
    }
  }

  Widget buildFollowUserSelection({
    required VoidCallback onClose,
    ScrollController? scrollController,
    ValueChanged<FollowUser>? onSelected,
    bool liveOnly = false,
    bool enableHoldPreview = false,
  }) {
    const options = ["全部", "直播中", "未开播"];
    return Obx(() {
      final filterMode = liveRoomFollowFilterMode.value;
      final followUsers = liveOnly
          ? FollowService.instance.sortFollowUsers(
              FollowService.instance.liveList,
            )
          : _followUsersByFilterMode(filterMode);
      return Stack(
        children: [
          Column(
            children: [
              if (!liveOnly)
                Padding(
                  padding: AppStyle.edgeInsetsA12.copyWith(bottom: 0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(options.length, (index) {
                        return Padding(
                          padding: EdgeInsets.only(
                            right: index == options.length - 1 ? 0 : 12,
                          ),
                          child: FilterButton(
                            text: options[index],
                            selected: filterMode == index,
                            onTap: () {
                              liveRoomFollowFilterMode.value = index;
                            },
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: FollowService.instance.loadData,
                  child: ListView.separated(
                    key: const PageStorageKey<String>(
                      "liveRoomFollowUserSelection",
                    ),
                    controller: scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: AppStyle.edgeInsetsA12.copyWith(bottom: 20),
                    itemCount: followUsers.length,
                    separatorBuilder: (_, __) => AppStyle.vGap8,
                    itemBuilder: (_, i) {
                      var item = followUsers[i];
                      return _buildLiveRoomFollowItem(
                        item: item,
                        onClose: onClose,
                        onSelected: onSelected,
                        enableHoldPreview: enableHoldPreview,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          if (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
            Positioned(
              right: 12,
              bottom: 12,
              child: Obx(
                () => DesktopRefreshButton(
                  refreshing: FollowService.instance.updating.value,
                  onPressed: FollowService.instance.loadData,
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _buildLiveRoomFollowItem({
    required FollowUser item,
    required VoidCallback onClose,
    ValueChanged<FollowUser>? onSelected,
    required bool enableHoldPreview,
  }) {
    return Obx(
      () => FollowUserItem(
        item: item,
        showSpecialMark: true,
        playing:
            rxSite.value.id == item.siteId && rxRoomId.value == item.roomId,
        onTap: rxSite.value.id == item.siteId &&
                rxRoomId.value == item.roomId &&
                onSelected != null
            ? null
            : () {
                onClose();
                if (onSelected != null) {
                  onSelected(item);
                } else {
                  resetRoom(
                    Sites.allSites[item.siteId]!,
                    item.roomId,
                  );
                }
              },
        onLongPress: !enableHoldPreview
            ? null
            : () {
                startFollowHoldPreview(item);
              },
        onLongPressEnd: !enableHoldPreview
            ? null
            : (_) {
                endFollowHoldPreview();
              },
        onLongPressCancel: !enableHoldPreview ? null : cancelFollowHoldPreview,
      ),
    );
  }

  bool get canStartInlineMultiRoom =>
      PlatformUtils.inlineMultiRoomUnavailableReason == null;

  void showAddToMultiRoomPanel() {
    final unavailableReason = PlatformUtils.inlineMultiRoomUnavailableReason;
    if (unavailableReason != null) {
      SmartDialog.showToast(unavailableReason);
      return;
    }
    if (detail.value == null) {
      SmartDialog.showToast("直播间信息还未加载完成");
      return;
    }

    Utils.showRightDialog(
      title: "添加直播间",
      width: 420,
      useSystem: false,
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: "关注（直播中）"),
                Tab(text: "历史"),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  buildFollowUserSelection(
                    onClose: Utils.hideRightDialog,
                    liveOnly: true,
                    onSelected: (item) {
                      unawaited(
                        _openInlineMultiRoom(MultiRoomItem.fromFollow(item)),
                      );
                    },
                  ),
                  buildHistorySelection(
                    onClose: Utils.hideRightDialog,
                    onSelected: (item, historySite) {
                      unawaited(
                        _openInlineMultiRoom(
                          MultiRoomItem(
                            site: historySite,
                            roomId: item.roomId,
                            userName: item.userName,
                            face: item.face,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openInlineMultiRoom(MultiRoomItem addedRoom) async {
    final roomDetail = detail.value;
    if (roomDetail == null || isPlayerClosing) {
      return;
    }
    final currentRoom = MultiRoomItem(
      site: site,
      roomId: roomId,
      userName: roomDetail.userName,
      face: roomDetail.userAvatar,
    );
    if (currentRoom.key == addedRoom.key) {
      SmartDialog.showToast("请选择另一个直播间");
      return;
    }

    // 等待右侧选择面板退场，避免遮罩与路由动画叠在一起。
    await Future.delayed(const Duration(milliseconds: 220));
    final shouldResumeSingleRoom = _shouldResumeAfterInlineMultiRoom();
    final positionBeforeMultiRoom = _lastKnownPlayerPosition;
    try {
      if (shouldResumeSingleRoom) {
        await _pauseForInlineMultiRoom();
      }
      final result = await AppNavigator.toMultiRoom(
        [currentRoom, addedRoom],
        returnToLiveRoom: true,
      );
      if (result is MultiRoomOpenSingleResult &&
          !_roomDisposed &&
          !isPlayerClosing) {
        await resetRoom(result.room.site, result.room.roomId);
      }
    } finally {
      if (!_roomDisposed && !isPlayerClosing) {
        if (shouldResumeSingleRoom) {
          await _resumeAfterInlineMultiRoom(positionBeforeMultiRoom);
        }
        if (fullScreenState.value) {
          await restoreFullScreenSystemUi();
        }
      }
    }
  }

  bool _shouldResumeAfterInlineMultiRoom() {
    if (Utils.isOhos) {
      final value = ohosVideoController?.value;
      return shouldResumeLiveRoomAfterInlineMultiRoom(
        playing: value?.isPlaying ?? false,
        buffering: value?.isBuffering ?? false,
      );
    }
    return shouldResumeLiveRoomAfterInlineMultiRoom(
      playing: player.state.playing,
      buffering: player.state.buffering,
    );
  }

  Future<void> _pauseForInlineMultiRoom() async {
    if (Utils.isOhos) {
      await ohosVideoController?.pause();
      return;
    }
    await suspendLiveLatencyChase(MpvLiveLatencyProtectionReason.sourceChanged);
    await player.pause();
  }

  Future<void> _resumeAfterInlineMultiRoom(
    Duration? positionBeforeMultiRoom,
  ) async {
    if (Utils.isOhos) {
      final controller = ohosVideoController;
      if (controller != null &&
          controller.value.isInitialized &&
          !controller.value.hasError) {
        await controller.play();
        updateOhosVideoState(controller.value);
      }
      return;
    }
    await player.play();
    await resumeLiveLatencyChase();
    await Future.delayed(const Duration(milliseconds: 800));
    if (_roomDisposed ||
        isPlayerClosing ||
        !liveStatus.value ||
        currentLineIndex < 0 ||
        playUrls.isEmpty) {
      return;
    }
    final stalled = !player.state.playing ||
        (positionBeforeMultiRoom != null &&
            _lastKnownPlayerPosition <= positionBeforeMultiRoom);
    if (stalled) {
      Log.d("多开返回后单直播间未恢复播放，重试 play()");
      await player.play();
      await resumeLiveLatencyChase();
    }
  }

  void showFollowUserSheet() {
    Utils.showBottomSheet(
      title: "关注列表",
      child: buildFollowUserSelection(
        onClose: Get.back,
        enableHoldPreview: true,
      ),
    );
  }

  void showAutoExitSheet() {
    Utils.showBottomSheet(
      title: "定时关闭",
      child: ListView(
        shrinkWrap: true,
        children: [
          Obx(
            () => SwitchListTile(
              title: Text(
                "启用定时关闭",
                style: Get.textTheme.titleMedium,
              ),
              value: autoExitEnable.value,
              onChanged: (e) {
                autoExitEnable.value = e;
                unawaited(AppSettingsController.instance.setAutoExitEnable(e));
                if (e) {
                  setAutoExit();
                } else {
                  stopAutoExit();
                }
              },
            ),
          ),
          Obx(
            () => ListTile(
              enabled: autoExitEnable.value,
              title: Text(
                "自动关闭时间：${autoExitMinutes.value ~/ 60}小时${autoExitMinutes.value % 60}分钟",
                style: Get.textTheme.titleMedium,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                var value = await showTimePicker(
                  context: Get.context!,
                  initialTime: TimeOfDay(
                    hour: autoExitMinutes.value ~/ 60,
                    minute: autoExitMinutes.value % 60,
                  ),
                  initialEntryMode: TimePickerEntryMode.inputOnly,
                  builder: (_, child) {
                    return MediaQuery(
                      data: Get.mediaQuery.copyWith(
                        alwaysUse24HourFormat: true,
                      ),
                      child: child!,
                    );
                  },
                );
                if (value == null || (value.hour == 0 && value.minute == 0)) {
                  return;
                }
                var duration =
                    Duration(hours: value.hour, minutes: value.minute);
                autoExitMinutes.value = duration.inMinutes;
                AppSettingsController.instance
                    .setRoomAutoExitDuration(autoExitMinutes.value);
                //setAutoExitDuration(duration.inMinutes);
                if (autoExitEnable.value) {
                  setAutoExit();
                } else {
                  countdown.value = autoExitMinutes.value * 60;
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void openNaviteAPP() async {
    var naviteUrl = "";
    var webUrl = "";
    if (site.id == Constant.kBiliBili) {
      naviteUrl = "bilibili://live/${detail.value?.roomId}";
      webUrl = "https://live.bilibili.com/${detail.value?.roomId}";
    } else if (site.id == Constant.kDouyin) {
      var args = detail.value?.danmakuData as DouyinDanmakuArgs;
      naviteUrl = "snssdk1128://webcast_room?room_id=${args.roomId}";
      webUrl = "https://live.douyin.com/${args.webRid}";
    } else if (site.id == Constant.kHuya) {
      var args = detail.value?.danmakuData as HuyaDanmakuArgs;
      naviteUrl =
          "yykiwi://homepage/index.html?banneraction=https%3A%2F%2Fdiy-front.cdn.huya.com%2Fzt%2Ffrontpage%2Fcc%2Fupdate.html%3Fhyaction%3Dlive%26channelid%3D${args.subSid}%26subid%3D${args.subSid}%26liveuid%3D${args.subSid}%26screentype%3D1%26sourcetype%3D0%26fromapp%3Dhuya_wap%252Fclick%252Fopen_app_guide%26&fromapp=huya_wap/click/open_app_guide";
      webUrl = "https://www.huya.com/${detail.value?.roomId}";
    } else if (site.id == Constant.kDouyu) {
      naviteUrl =
          "douyulink://?type=90001&schemeUrl=douyuapp%3A%2F%2Froom%3FliveType%3D0%26rid%3D${detail.value?.roomId}";
      webUrl = "https://www.douyu.com/${detail.value?.roomId}";
    }
    try {
      await launchUrlString(naviteUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("无法打开 APP，将使用浏览器打开");
      await launchUrlString(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> resetRoom(
    Site site,
    String roomId, {
    bool fromHoldPreview = false,
  }) async {
    if (!fromHoldPreview) {
      await closeFollowHoldPreview();
    }
    if (this.site == site && this.roomId == roomId) {
      return;
    }

    if (_roomSwitching) {
      _pendingRoomSite = site;
      _pendingRoomId = roomId;
      return;
    }

    _roomSwitching = true;
    try {
      while (true) {
        final currentSite = site;
        final currentRoomId = roomId;
        rxSite.value = currentSite;
        rxRoomId.value = currentRoomId;
        CurrentRoomService.instance.setRoom(currentSite, currentRoomId);
        _roomDisposed = false;
        _loadGeneration += 1;
        await resetLiveLatencyChase();
        _onlineRefreshFailures = 0;
        tempMutedUsers.clear();
        danmakuViewportHeight.value = 0;

        // 清理当前房间的会话状态
        await liveDanmaku.stop();
        messages.clear();
        _clearDanmuDedupeState();
        _clearSuperChatState();
        _clearContributionRankState();
        clearLiveEventFlow();
        _cancelPendingDanmakuTimers();
        clearDanmakuReplayHistory();
        danmakuController?.clear();
        rebuildDanmakuView();

        // 重新创建弹幕连接对象
        liveDanmaku = currentSite.liveSite.getDanmaku();

        // 停止当前播放
        _stopLiveLatencyTelemetry();
        await stopBackgroundPlaybackService();
        if (!Utils.isOhos) {
          await player.stop();
        }

        // 换房清理网络诊断与自动降画质会话（S3-T2）：
        // 诊断计数/冷却/提示/Timer 与诊断代次一起重置，旧房间异步结果不得串房；
        // 降画质 tracker 的计数与降档冷却一并清零，新流打开时的
        // beginWarmup 语义保留。
        _resetPlaybackHealthSession();

        // 重新拉取房间信息
        loadData();
        await restoreUserIntentPlayerVolumeForRoom();

        final pendingSite = _pendingRoomSite;
        final pendingRoomId = _pendingRoomId;
        _pendingRoomSite = null;
        _pendingRoomId = null;
        if (pendingSite == null || pendingRoomId == null) {
          break;
        }
        site = pendingSite;
        roomId = pendingRoomId;
      }
    } finally {
      _roomSwitching = false;
    }
  }

  void copyErrorDetail() {
    Utils.copyToClipboard('''直播平台：${rxSite.value.name}
房间号：${rxRoomId.value}
错误信息：
${error?.toString()}
----------------
${errorStackTrace ?? ""}''');
    SmartDialog.showToast("已复制错误信息");
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    refreshIosVideoOutputLimit(force: true);
    _markHoldPreviewOverlayNeedsBuild();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(closeFollowHoldPreview());
      Log.d("进入后台:$state");
      unawaited(
        suspendLiveLatencyChase(
          MpvLiveLatencyProtectionReason.lifecycleInterrupted,
        ),
      );
      recordLiveLinkHealthEvent(LiveLinkEventType.appBackgrounded);
      isBackground = true;
      _backgroundedAt ??= DateTime.now();
      _positionBeforeBackground ??= _lastKnownPlayerPosition;
      if (!Utils.isOhos) {
        // 记录后台前的播放状态，供回前台时判断是否真的需要恢复播放。
        _wasPlayingBeforeBackground ??= player.state.playing;
      }
      if (Utils.isOhos && _ohosWasPlayingBeforeBackground == null) {
        _ohosWasPlayingBeforeBackground = ohosPlaying.value;
        if (!_allowBackgroundPlayback && !pipPlaybackActiveOrPrepared) {
          unawaited(ohosVideoController?.pause());
        }
      }
      if (!_allowBackgroundPlayback && !Utils.isOhos) {
        unawaited(
          AppSettingsController.instance.saveLastLiveRoom(
            siteId: site.id,
            roomId: roomId,
            resumePending: true,
          ),
        );
      }
    } else if (state == AppLifecycleState.resumed) {
      Log.d("返回前台");
      recordLiveLinkHealthEvent(LiveLinkEventType.appForegrounded);
      _refreshAutoExitCountdown();
      isBackground = false;
      unawaited(
        AppSettingsController.instance.setLastLiveRoomResumePending(false),
      );
      _refreshDanmakuOverlay("返回前台");
      var backgroundedAt = _backgroundedAt;
      var positionBeforeBackground = _positionBeforeBackground;
      var ohosWasPlayingBeforeBackground = _ohosWasPlayingBeforeBackground;
      var wasPlayingBeforeBackground = _wasPlayingBeforeBackground;
      // Always release the lifecycle gate. The user-pause gate remains
      // independent, so this does not restart a stream paused by the user.
      unawaited(resumeLiveLatencyChase(appForegrounded: true));
      _backgroundedAt = null;
      _positionBeforeBackground = null;
      _ohosWasPlayingBeforeBackground = null;
      _wasPlayingBeforeBackground = null;
      unawaited(
        _recoverPlaybackAfterForeground(
          "返回前台",
          since: backgroundedAt,
          previousPosition: positionBeforeBackground,
          ohosWasPlaying: ohosWasPlayingBeforeBackground,
          wasPlaying: wasPlayingBeforeBackground,
        ),
      );
    } else if (state == AppLifecycleState.inactive) {
      Log.d("应用短暂失焦:$state");
      unawaited(() async {
        await closeFollowHoldPreview();
        await syncAutoPipOnLeave();
      }());
    }
  }

  Future<void> _recoverPlaybackAfterForeground(
    String reason, {
    required DateTime? since,
    required Duration? previousPosition,
    required bool? ohosWasPlaying,
    required bool? wasPlaying,
  }) async {
    if (Utils.isOhos) {
      if (ohosWasPlaying != true ||
          since == null ||
          !liveStatus.value ||
          currentLineIndex < 0 ||
          playUrls.isEmpty ||
          DateTime.now().difference(since) < const Duration(seconds: 3)) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
      if (isBackground) {
        return;
      }
      final controller = ohosVideoController;
      if (controller != null &&
          controller.value.isInitialized &&
          !controller.value.hasError) {
        if (!controller.value.isPlaying) {
          try {
            await controller.play();
            updateOhosVideoState(controller.value);
            return;
          } catch (e) {
            Log.d("$reason 后恢复鸿蒙播放器失败，准备重新加载: $e");
          }
        } else {
          // 仍在"播放"不代表流健康：断流后 HLS 直播窗口停滞，AVPlayer 可能
          // 停在最后一个 GOP 长时间无进度。先检测断流（异常/长时间无进度），
          // 命中就走 setPlayer(refreshUrls) 重连，避免 play() 造成假播放。
          if (_ohosPlaybackLooksStalled(controller)) {
            Log.d("$reason 后鸿蒙播放器疑似断流，重新加载");
            await setPlayer(
              refreshUrls: false,
              reconnectReason: LiveReconnectReason.playbackUrlRefresh,
            );
            return;
          }
          return;
        }
      }
      await setPlayer(
        refreshUrls: false,
        reconnectReason: LiveReconnectReason.playbackUrlRefresh,
      );
      return;
    }
    if (since == null ||
        previousPosition == null ||
        wasPlaying != true ||
        !liveStatus.value ||
        currentLineIndex < 0 ||
        playUrls.isEmpty) {
      return;
    }
    if (DateTime.now().difference(since) < const Duration(seconds: 3)) {
      return;
    }
    await Future.delayed(const Duration(milliseconds: 1200));
    if (isBackground) {
      return;
    }
    var currentPosition = _lastKnownPlayerPosition;
    var stalled = currentPosition <= previousPosition ||
        player.state.buffering ||
        player.state.completed ||
        !player.state.playing;
    if (!stalled) {
      return;
    }
    Log.d("$reason 后检测到播放停滞，尝试恢复");
    await setPlayer(
      refreshUrls: _shouldRefreshUrlsOnPlaybackRetry,
      reconnectReason: LiveReconnectReason.playbackUrlRefresh,
    );
  }

  /// 返回前台时判定鸿蒙 AVPlayer 是否已断流：出错或长时间无进度推进。
  ///
  /// 允许后台继续播放时，断流后 HLS 直播窗口会停滞，position 不再推进；
  /// 与 [updateOhosVideoState] 维护的最后健康进度对比即可发现假播放。
  ///
  /// 分层兜底：position 不可用（部分直播源 currentTime 恒为 -1）时退到原生心跳；
  /// 两者都没有过任何证据时保守视为健康，交给正常 play() 路径，宁可漏判也不要
  /// 把一路正常播放的画面重连掉。
  bool _ohosPlaybackLooksStalled(VideoPlayerController controller) {
    final value = controller.value;
    if (value.hasError) {
      return true;
    }
    if (!value.isPlaying) {
      return false;
    }
    if (_lastOhosPlaybackPosition > Duration.zero) {
      return !didOhosPlaybackTimelineProgress(
        current: value.position,
        previous: _lastOhosPlaybackPosition,
      );
    }
    if (_ohosLastHeartbeatAt != null) {
      return !_ohosHeartbeatLooksAlive(DateTime.now());
    }
    return false;
  }

  @override
  void onWindowBlur() {
    _windowBlurredAt = DateTime.now();
    _positionBeforeWindowBlur = _lastKnownPlayerPosition;
    _wasPlayingBeforeWindowBlur = player.state.playing;
  }

  @override
  void onWindowFocus() {
    var windowBlurredAt = _windowBlurredAt;
    var positionBeforeWindowBlur = _positionBeforeWindowBlur;
    var wasPlayingBeforeWindowBlur = _wasPlayingBeforeWindowBlur;
    _windowBlurredAt = null;
    _positionBeforeWindowBlur = null;
    _wasPlayingBeforeWindowBlur = null;
    _refreshDanmakuOverlay("窗口重新聚焦");
    unawaited(
      _recoverPlaybackAfterForeground(
        "窗口重新聚焦",
        since: windowBlurredAt,
        previousPosition: positionBeforeWindowBlur,
        ohosWasPlaying: null,
        wasPlaying: wasPlayingBeforeWindowBlur,
      ),
    );
  }

  // 启动并更新开播时长计时器
  void startLiveDurationTimer() {
    // 非开播状态，或没有 showTime 时，不启动计时器。
    if (!(detail.value?.status ?? false) || detail.value?.showTime == null) {
      liveDuration.value = "00:00:00"; // 未开播时显示 00:00:00
      _liveDurationTimer?.cancel();
      return;
    }

    try {
      int startTimeStamp = int.parse(detail.value!.showTime!);
      // 先取消旧计时器，再启动新的。
      _liveDurationTimer?.cancel();
      _liveDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        int currentTimeStamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        int durationInSeconds = currentTimeStamp - startTimeStamp;

        int hours = durationInSeconds ~/ 3600;
        int minutes = (durationInSeconds % 3600) ~/ 60;
        int seconds = durationInSeconds % 60;

        String formattedDuration =
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        liveDuration.value = formattedDuration;
      });
    } catch (e) {
      liveDuration.value = "--:--:--"; // 解析失败时显示占位值
    }
  }

  // ignore: unused_element
  void _legacyOnClose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isWindows) {
      windowManager.removeListener(this);
    }
    scrollController.removeListener(scrollListener);
    autoExitTimer?.cancel();
    _positionSubscription?.cancel();

    liveDanmaku.stop();
    danmakuController = null;
    _liveDurationTimer?.cancel(); // 页面关闭时取消计时器
    super.onClose();
  }
}
