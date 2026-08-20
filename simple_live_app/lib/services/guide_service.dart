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
  final Rxn<GuideFlowState> activeFlow = Rxn<GuideFlowState>();
  final RxBool overlayVisible = false.obs;
  final RxBool dimBackground = true.obs;
  final Rxn<Rect> focusRect = Rxn<Rect>();

  bool get isActive => activeFlow.value != null;

  void start(GuideFlowState flow) {
    activeFlow.value = flow;
    overlayVisible.value = true;
    _applyCurrentStep();
  }

  void dismiss() {
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
    focusRect.value = rect;
  }

  void syncFocusRectFromKey(GlobalKey key, {double inflateBy = 6}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rect = rectFromKey(key, inflateBy: inflateBy);
      if (rect != null) {
        setFocusRect(rect);
      }
    });
  }

  Rect? rectFromKey(GlobalKey key, {double inflateBy = 6}) {
    final context = key.currentContext;
    if (context == null) {
      return null;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) {
      return null;
    }
    return (renderObject.localToGlobal(Offset.zero) & renderObject.size)
        .inflate(inflateBy);
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
