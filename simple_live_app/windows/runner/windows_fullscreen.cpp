#include "windows_fullscreen.h"

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
  SetWindowLongPtr(window, GWL_STYLE, fullscreen_style);
  SetWindowLongPtr(window, GWL_EXSTYLE, ex_style_);

  const RECT& monitor_rect = monitor_info.rcMonitor;
  if (!SetWindowPos(window, HWND_TOP, monitor_rect.left, monitor_rect.top,
                    monitor_rect.right - monitor_rect.left,
                    monitor_rect.bottom - monitor_rect.top,
                    SWP_FRAMECHANGED | SWP_SHOWWINDOW)) {
    SetWindowLongPtr(window, GWL_STYLE, style_);
    SetWindowLongPtr(window, GWL_EXSTYLE, ex_style_);
    return false;
  }
  active_ = true;
  return true;
}

bool WindowsFullscreenController::Exit(HWND window) {
  if (!window || !active_) {
    return !active_;
  }

  SetWindowLongPtr(window, GWL_STYLE, style_);
  SetWindowLongPtr(window, GWL_EXSTYLE, ex_style_);
  const bool placement_restored = SetWindowPlacement(window, &placement_) != FALSE;
  const bool frame_updated = SetWindowPos(
      window, nullptr, 0, 0, 0, 0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
          SWP_FRAMECHANGED) != FALSE;
  if (placement_restored) {
    ShowWindow(window, placement_.showCmd);
  }
  active_ = false;
  return placement_restored && frame_updated;
}
