#include "windows_fullscreen.h"

#include <dwmapi.h>

namespace {

// DWMWA_TRANSITIONS_FORCEDISABLED was added after the oldest Windows SDKs
// supported by the runner. Keep the numeric value local so this still builds
// with those SDKs while DwmSetWindowAttribute handles runtime support.
constexpr auto kDwmTransitionsForcedDisabled =
    static_cast<DWMWINDOWATTRIBUTE>(3);

struct DwmTransitionState {
  BOOL previous_value = FALSE;
  bool previous_value_read = false;
  bool changed = false;
};

DwmTransitionState DisableDwmTransitions(HWND window) {
  DwmTransitionState state;
  state.previous_value_read =
      SUCCEEDED(DwmGetWindowAttribute(
          window, kDwmTransitionsForcedDisabled, &state.previous_value,
          sizeof(state.previous_value)));

  const BOOL disabled = TRUE;
  state.changed =
      SUCCEEDED(DwmSetWindowAttribute(window, kDwmTransitionsForcedDisabled,
                                      &disabled, sizeof(disabled)));
  return state;
}

void RestoreDwmTransitions(HWND window, const DwmTransitionState& state) {
  if (!state.changed) {
    return;
  }

  const BOOL value = state.previous_value_read ? state.previous_value : FALSE;
  DwmSetWindowAttribute(window, kDwmTransitionsForcedDisabled, &value,
                        sizeof(value));
}

void RedrawNonClientArea(HWND window) {
  RedrawWindow(window, nullptr, nullptr,
               RDW_FRAME | RDW_INVALIDATE | RDW_UPDATENOW);
}

}  // namespace

bool WindowsFullscreenController::Enter(HWND window) {
  if (!window || active_) {
    return active_;
  }

  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  if (!GetWindowPlacement(window, &placement)) {
    return false;
  }
  const HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{sizeof(monitor_info)};
  if (!GetMonitorInfo(monitor, &monitor_info)) {
    return false;
  }

  placement_ = placement;
  style_ = GetWindowLongPtr(window, GWL_STYLE);
  ex_style_ = GetWindowLongPtr(window, GWL_EXSTYLE);
  const LONG_PTR fullscreen_style = style_ & ~static_cast<LONG_PTR>(WS_OVERLAPPEDWINDOW);

  const DwmTransitionState dwm_transition_state =
      DisableDwmTransitions(window);
  previous_dwm_transitions_ = dwm_transition_state.previous_value;
  previous_dwm_transitions_read_ = dwm_transition_state.previous_value_read;
  dwm_transitions_changed_ = dwm_transition_state.changed;
  SetWindowLongPtr(window, GWL_STYLE, fullscreen_style);
  SetWindowLongPtr(window, GWL_EXSTYLE, ex_style_);

  // Mark the frame as fullscreen before SetWindowPos sends WM_NCCALCSIZE.
  // FlutterWindow can then expand the client area during this same transition
  // instead of allowing one frame with the old non-client border.
  active_ = true;

  const RECT& monitor_rect = monitor_info.rcMonitor;
  if (!SetWindowPos(window, HWND_TOP, monitor_rect.left, monitor_rect.top,
                    monitor_rect.right - monitor_rect.left,
                    monitor_rect.bottom - monitor_rect.top,
                    SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOOWNERZORDER |
                        SWP_NOACTIVATE | SWP_NOCOPYBITS)) {
    SetWindowLongPtr(window, GWL_STYLE, style_);
    SetWindowLongPtr(window, GWL_EXSTYLE, ex_style_);
    active_ = false;
    RedrawNonClientArea(window);
    RestoreDwmTransitions(window, dwm_transition_state);
    dwm_transitions_changed_ = false;
    return false;
  }

  RedrawNonClientArea(window);
  return true;
}

bool WindowsFullscreenController::CompleteEnter(HWND window) {
  if (!window || !active_) {
    return false;
  }

  if (!dwm_transitions_changed_) {
    return true;
  }

  // Let the resized, borderless frame reach DWM before transitions are
  // enabled again. This prevents the previous non-client frame from being
  // presented during the first fullscreen composition.
  RedrawNonClientArea(window);
  DwmFlush();
  const DwmTransitionState state{
      previous_dwm_transitions_, previous_dwm_transitions_read_,
      dwm_transitions_changed_};
  RestoreDwmTransitions(window, state);
  dwm_transitions_changed_ = false;
  return true;
}

bool WindowsFullscreenController::Exit(HWND window) {
  if (!window || !active_) {
    return !active_;
  }

  const DwmTransitionState dwm_transition_state =
      DisableDwmTransitions(window);
  if (dwm_transitions_changed_) {
    const DwmTransitionState enter_state{
        previous_dwm_transitions_, previous_dwm_transitions_read_,
        dwm_transitions_changed_};
    RestoreDwmTransitions(window, enter_state);
    dwm_transitions_changed_ = false;
  }
  // The regular frame is being restored below. Let WM_NCCALCSIZE calculate
  // the normal client area while the placement is applied.
  active_ = false;
  SetWindowLongPtr(window, GWL_STYLE, style_);
  SetWindowLongPtr(window, GWL_EXSTYLE, ex_style_);
  const bool placement_restored = SetWindowPlacement(window, &placement_) != FALSE;
  const bool frame_updated = SetWindowPos(
      window, nullptr, 0, 0, 0, 0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
          SWP_NOACTIVATE | SWP_FRAMECHANGED) != FALSE;
  RedrawNonClientArea(window);
  if (placement_restored) {
    ShowWindow(window, placement_.showCmd);
  }
  RestoreDwmTransitions(window, dwm_transition_state);
  return placement_restored && frame_updated;
}
