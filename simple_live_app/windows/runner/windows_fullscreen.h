#ifndef RUNNER_WINDOWS_FULLSCREEN_H_
#define RUNNER_WINDOWS_FULLSCREEN_H_

#include <windows.h>

// Owns the borderless fullscreen transition for the Flutter top-level window.
// The original style and placement are restored exactly, including a prior
// maximized state.
class WindowsFullscreenController {
 public:
  bool Enter(HWND window);
  bool Exit(HWND window);
  bool IsActive() const { return active_; }

 private:
  LONG_PTR style_ = 0;
  LONG_PTR ex_style_ = 0;
  WINDOWPLACEMENT placement_{};
  bool active_ = false;
};

#endif  // RUNNER_WINDOWS_FULLSCREEN_H_
