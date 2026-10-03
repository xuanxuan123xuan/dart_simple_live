import 'package:flutter/material.dart';
import 'package:get/get.dart';

enum GuideStepKind {
  searchField,
}

class GuideStep {
  const GuideStep({
    required this.kind,
    required this.title,
    required this.message,
    this.highlightRect,
    this.allowTapThrough = false,
  });

  final GuideStepKind kind;
  final String title;
  final String message;
  final Rect? highlightRect;
  final bool allowTapThrough;
}

class GuideFlowState {
  GuideFlowState({required this.steps});

  final List<GuideStep> steps;
  int index = 0;

  GuideStep get current => steps[index];
  bool get hasNext => index + 1 < steps.length;

  void next() {
    if (hasNext) {
      index += 1;
    }
  }
}

class GuideService extends GetxService {
  final GlobalKey overlayKey = GlobalKey(debugLabel: 'guideOverlay');
  final Rxn<GuideFlowState> activeFlow = Rxn<GuideFlowState>();
  final RxBool overlayVisible = false.obs;
  final RxBool dimBackground = true.obs;
  final Rxn<Rect> focusRect = Rxn<Rect>();
  int _focusTrackingId = 0;

  bool get isActive => activeFlow.value != null;

  void start(GuideFlowState flow) {
    _stopFocusTracking();
    activeFlow.value = flow;
    overlayVisible.value = true;
    _applyCurrentStep();
  }

  void dismiss() {
    _stopFocusTracking();
    activeFlow.value = null;
    overlayVisible.value = false;
    focusRect.value = null;
  }

  void nextStep() {
    final flow = activeFlow.value;
    if (flow == null) {
      return;
    }
    if (flow.hasNext) {
      flow.next();
      _applyCurrentStep();
      activeFlow.refresh();
      return;
    }
    dismiss();
  }

  void setFocusRect(Rect? rect) {
    if (focusRect.value != rect) {
      focusRect.value = rect;
    }
  }

  void trackFocusRectFromKey(GlobalKey key, {double inflateBy = 0}) {
    final trackingId = ++_focusTrackingId;

    void syncAfterFrame(Duration _) {
      if (trackingId != _focusTrackingId || !isActive) {
        return;
      }
      final rect = rectFromKey(key, inflateBy: inflateBy);
      if (rect != null) {
        setFocusRect(rect);
      }
      WidgetsBinding.instance.addPostFrameCallback(syncAfterFrame);
    }

    WidgetsBinding.instance.addPostFrameCallback(syncAfterFrame);
  }

  Rect? rectFromKey(GlobalKey key, {double inflateBy = 0}) {
    final targetContext = key.currentContext;
    final overlayContext = overlayKey.currentContext;
    if (targetContext == null || overlayContext == null) {
      return null;
    }
    final target = targetContext.findRenderObject();
    final overlay = overlayContext.findRenderObject();
    if (target is! RenderBox ||
        overlay is! RenderBox ||
        !target.attached ||
        !overlay.attached) {
      return null;
    }

    final globalTopLeft = target.localToGlobal(Offset.zero);
    final globalBottomRight = target.localToGlobal(target.size.bottomRight(
      Offset.zero,
    ));
    final topLeft = overlay.globalToLocal(globalTopLeft);
    final bottomRight = overlay.globalToLocal(globalBottomRight);
    if (!topLeft.dx.isFinite ||
        !topLeft.dy.isFinite ||
        !bottomRight.dx.isFinite ||
        !bottomRight.dy.isFinite) {
      return null;
    }
    return Rect.fromPoints(topLeft, bottomRight).inflate(inflateBy);
  }

  void _stopFocusTracking() {
    _focusTrackingId += 1;
  }

  void startSearchGuide() {
    start(
      GuideFlowState(
        steps: const [
          GuideStep(
            kind: GuideStepKind.searchField,
            title: '链接解析',
            message: '在搜索框里输入房间号、主播名，或者直接粘贴直播链接。',
            allowTapThrough: true,
          ),
        ],
      ),
    );
  }

  void _applyCurrentStep() {
    final step = activeFlow.value?.current;
    if (step == null) {
      focusRect.value = null;
      return;
    }
    focusRect.value = step.highlightRect;
    dimBackground.value = step.highlightRect != null;
  }
}
