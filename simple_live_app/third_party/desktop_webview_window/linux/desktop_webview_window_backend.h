#ifndef DESKTOP_WEBVIEW_WINDOW_LINUX_BACKEND_H_
#define DESKTOP_WEBVIEW_WINDOW_LINUX_BACKEND_H_

#include <flutter_linux/flutter_linux.h>

// Keep the lazy backend boundary free of WebKit types: missing host libraries
// must not prevent the Flutter application itself from starting.
using WebviewBackendCreate = GObject *(*)(FlPluginRegistrar *, FlMethodChannel *);
using WebviewBackendHandleMethod = void (*)(GObject *, FlMethodCall *);

extern "C" {

__attribute__((visibility("default"))) GObject *
desktop_webview_window_backend_create(FlPluginRegistrar *registrar,
                                     FlMethodChannel *channel);

__attribute__((visibility("default"))) void
desktop_webview_window_backend_handle_method(GObject *backend,
                                            FlMethodCall *method_call);

}

#endif  // DESKTOP_WEBVIEW_WINDOW_LINUX_BACKEND_H_
