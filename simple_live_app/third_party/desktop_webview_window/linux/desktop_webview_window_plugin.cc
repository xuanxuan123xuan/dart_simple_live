#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "include/desktop_webview_window/desktop_webview_window_plugin.h"

#include <dlfcn.h>

#include <cstdlib>
#include <cstring>

#include "desktop_webview_window_backend.h"

namespace {

struct BackendLibrary {
  void *handle = nullptr;
  WebviewBackendCreate create = nullptr;
  WebviewBackendHandleMethod handle_method = nullptr;
};

const BackendLibrary &GetBackendLibrary() {
  static const BackendLibrary library = []() {
    BackendLibrary result;
    Dl_info plugin_info = {};
    if (dladdr(reinterpret_cast<void *>(&GetBackendLibrary),
               &plugin_info) == 0 ||
        plugin_info.dli_fname == nullptr) {
      g_warning("desktop_webview_window: cannot locate the Linux WebKit backend");
      return result;
    }

    // Resolve our own .so first; never search the working directory or an
    // environment-supplied backend path. Both libraries live in bundle/lib.
    g_autofree gchar *plugin_path = realpath(plugin_info.dli_fname, nullptr);
    if (plugin_path == nullptr) {
      g_warning("desktop_webview_window: cannot resolve the plugin library path");
      return result;
    }
    g_autofree gchar *directory = g_path_get_dirname(plugin_path);
    g_autofree gchar *backend_path = g_build_filename(
        directory, "libdesktop_webview_window_webkit.so", nullptr);
    void *handle = dlopen(backend_path, RTLD_NOW | RTLD_LOCAL);
    if (handle == nullptr) {
      g_warning("desktop_webview_window: Linux WebKitGTK is unavailable: %s",
                dlerror());
      return result;
    }

    auto create = reinterpret_cast<WebviewBackendCreate>(
        dlsym(handle, "desktop_webview_window_backend_create"));
    auto handle_method = reinterpret_cast<WebviewBackendHandleMethod>(
        dlsym(handle, "desktop_webview_window_backend_handle_method"));
    if (create == nullptr || handle_method == nullptr) {
      g_warning("desktop_webview_window: incompatible Linux WebKit backend");
      dlclose(handle);
      return result;
    }

    result.handle = handle;
    result.create = create;
    result.handle_method = handle_method;
    // GTypes and pending WebKit callbacks can outlive an individual registrar.
    // Keep a successful library handle open for the rest of the process.
    return result;
  }();
  return library;
}

class WebviewWindowLoader {
 public:
  explicit WebviewWindowLoader(FlPluginRegistrar *registrar)
      : registrar_(FL_PLUGIN_REGISTRAR(g_object_ref(registrar))) {}

  ~WebviewWindowLoader() {
    g_clear_object(&backend_);
    g_clear_object(&registrar_);
  }

  void HandleMethodCall(FlMethodChannel *channel, FlMethodCall *method_call) {
    const auto &library = GetBackendLibrary();
    if (strcmp(fl_method_call_get_name(method_call), "isWebviewAvailable") == 0) {
      g_autoptr(FlValue) available = fl_value_new_bool(library.handle != nullptr);
      fl_method_call_respond_success(method_call, available, nullptr);
      return;
    }
    if (library.handle == nullptr) {
      fl_method_call_respond_error(
          method_call, "linux_webkit_runtime_unavailable",
          "The Linux WebKitGTK runtime could not be loaded. Install a "
          "compatible WebKitGTK runtime and restart the app.",
          nullptr, nullptr);
      return;
    }
    if (backend_ == nullptr) {
      backend_ = library.create(registrar_, channel);
    }
    library.handle_method(backend_, method_call);
  }

 private:
  FlPluginRegistrar *registrar_;
  GObject *backend_ = nullptr;
};

}  // namespace

void desktop_webview_window_plugin_register_with_registrar(
    FlPluginRegistrar *registrar) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "webview_window",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel,
      [](FlMethodChannel *channel, FlMethodCall *call, gpointer user_data) {
        static_cast<WebviewWindowLoader *>(user_data)->HandleMethodCall(channel,
                                                                       call);
      },
      new WebviewWindowLoader(registrar),
      [](gpointer user_data) {
        delete static_cast<WebviewWindowLoader *>(user_data);
      });
}
