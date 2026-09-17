import 'package:simple_live_core/simple_live_core.dart';

/// Connect on initial live entry or after an offline room becomes live.
/// Polling an already-live room must not create duplicate connections.
bool shouldStartDouyinDanmaku(
  LiveStatusState? previous,
  LiveStatusState current,
) =>
    current == LiveStatusState.live && previous != LiveStatusState.live;
