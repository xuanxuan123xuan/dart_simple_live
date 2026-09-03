// Milestone 0 verification bridge: libmpv -> Flutter SurfaceTextureEntry.
//
// Threading rules from integration README section 4:
//  - a dedicated thread pumps mpv_wait_event and hands events to ArkTS via
//    napi_threadsafe_function (never touch napi from mpv callback context);
//  - property writes are async (sync writes from the UI thread hit XCollie).
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <chrono>
#include <thread>

#include "napi/native_api.h"
#include "hilog/log.h"
#include <mpv/client.h>
#include <native_window/external_window.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200
#define LOG_TAG "MpvNapi"

namespace {

struct EventPayload {
    std::string kind;
    std::string name;
    std::string value;
    std::string text;
    int32_t gen = 0;
};

std::atomic<int32_t> g_eventGeneration{0};
std::atomic<bool> g_running{false};
std::atomic<bool> g_callbackSet{false};
mpv_handle *g_mpv = nullptr;
std::thread g_eventThread;
napi_threadsafe_function g_tsf = nullptr;
OHNativeWindow *g_nativeWindow = nullptr;

void LogMpv(int priority, const char *msg) {
    OH_LOG_Print(static_cast<LogType>(LOG_APP), static_cast<LogLevel>(priority), LOG_DOMAIN, LOG_TAG, "%{public}s", msg);
}

void QueueEvent(EventPayload *payload) {
    if (!g_callbackSet) {
        delete payload;
        return;
    }
    payload->gen = g_eventGeneration.load();
    // Payload ownership transfers to the TSF callback; freed there.
    napi_call_threadsafe_function(g_tsf, payload, napi_tsfn_nonblocking);
}

int32_t g_geoW = 0;
int32_t g_geoH = 0;

// Lightweight: never touches mpv state (a synchronous vo teardown here
// blocked the event pump and caused black-frame loops). Only notifies Dart,
// which owns the full vo hot-reconfig sequence via async method calls.
void HandleNativeWindowGeometry(int width, int height) {
    if (width <= 0 || height <= 0) {
        return;
    }
    if (width == g_geoW && height == g_geoH) {
        return;
    }
    char sizeOpt[64] = {0};
    snprintf(sizeOpt, sizeof(sizeOpt), "%dx%d", width, height);
    auto *payload = new EventPayload();
    payload->kind = "event";
    payload->name = "geometry-changed";
    payload->value = sizeOpt;
    QueueEvent(payload);
}

// Applies the requested buffer geometry. Called from Dart as part of the
// async vo reconfig sequence (vo=null -> setGeometry -> ohos-surface-size
// -> vo=gpu-next).
napi_value SetGeometry(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2 || g_nativeWindow == nullptr) {
        return nullptr;
    }
    double w = 0;
    double h = 0;
    napi_get_value_double(env, args[0], &w);
    napi_get_value_double(env, args[1], &h);
    if (w < 16 || h < 16) {
        return nullptr;
    }
    int32_t code = OH_NativeWindow_NativeWindowHandleOpt(
        g_nativeWindow, SET_BUFFER_GEOMETRY,
        static_cast<int32_t>(w), static_cast<int32_t>(h));
    if (code == 0) {
        g_geoW = static_cast<int32_t>(w);
        g_geoH = static_cast<int32_t>(h);
    }
    OH_LOG_Print(static_cast<LogType>(LOG_APP), LOG_INFO, LOG_DOMAIN, LOG_TAG,
                 "setGeometry %{public}dx%{public}d code=%{public}d",
                 static_cast<int>(w), static_cast<int>(h), code);
    return nullptr;
}

std::atomic<int64_t> g_lastTimePosPushMs{0};
std::atomic<int64_t> g_lastCachePushMs{0};

void EventLoop() {
    while (g_running.load()) {
        mpv_event *ev = mpv_wait_event(g_mpv, 0.25);
        if (ev == nullptr || ev->event_id == MPV_EVENT_NONE) {
            continue;
        }
        switch (ev->event_id) {
            case MPV_EVENT_PROPERTY_CHANGE: {
                auto *prop = static_cast<mpv_event_property *>(ev->data);
                auto *payload = new EventPayload();
                payload->kind = "property";
                payload->name = prop->name;
                if (prop->format == MPV_FORMAT_STRING && prop->data != nullptr) {
                    payload->value = *static_cast<const char **>(prop->data);
                } else if (prop->format == MPV_FORMAT_FLAG && prop->data != nullptr) {
                    payload->value = *static_cast<int *>(prop->data) != 0 ? "true" : "false";
                } else if (prop->format == MPV_FORMAT_INT64 && prop->data != nullptr) {
                    payload->value = std::to_string(*static_cast<int64_t *>(prop->data));
                } else if (prop->format == MPV_FORMAT_DOUBLE && prop->data != nullptr) {
                    payload->value = std::to_string(*static_cast<double *>(prop->data));
                } else {
                    payload->value = "";
                }
                if (prop->name == std::string("video-out-params")) {
                    int64_t dw = 0;
                    int64_t dh = 0;
                    if (mpv_get_property(g_mpv, "video-out-params/dw", MPV_FORMAT_INT64, &dw) >= 0 &&
                        mpv_get_property(g_mpv, "video-out-params/dh", MPV_FORMAT_INT64, &dh) >= 0) {
                        HandleNativeWindowGeometry(static_cast<int>(dw), static_cast<int>(dh));
                    }
                }
                if (prop->name == std::string("time-pos") ||
                    prop->name == std::string("demuxer-cache-time")) {
                    int64_t now = std::chrono::duration_cast<std::chrono::milliseconds>(
                        std::chrono::steady_clock::now().time_since_epoch()).count();
                    int64_t last = prop->name == std::string("time-pos")
                        ? g_lastTimePosPushMs.load()
                        : g_lastCachePushMs.load();
                    if (now - last < 250) {
                        delete payload;
                        break;
                    }
                    if (prop->name == std::string("time-pos")) {
                        g_lastTimePosPushMs.store(now);
                    } else {
                        g_lastCachePushMs.store(now);
                    }
                }
                QueueEvent(payload);
                break;
            }
            case MPV_EVENT_LOG_MESSAGE: {
                auto *msg = static_cast<mpv_event_log_message *>(ev->data);
                auto *payload = new EventPayload();
                payload->kind = "log";
                payload->name = msg->prefix;
                payload->text = std::string(msg->text);
                QueueEvent(payload);
                break;
            }
            case MPV_EVENT_END_FILE: {
                auto *eef = static_cast<mpv_event_end_file *>(ev->data);
                const char *reason = "unknown";
                switch (eef->reason) {
                    case MPV_END_FILE_REASON_EOF: reason = "eof"; break;
                    case MPV_END_FILE_REASON_STOP: reason = "stop"; break;
                    case MPV_END_FILE_REASON_QUIT: reason = "quit"; break;
                    case MPV_END_FILE_REASON_ERROR: reason = "error"; break;
                    case MPV_END_FILE_REASON_REDIRECT: reason = "redirect"; break;
                    default: break;
                }
                auto *payload = new EventPayload();
                payload->kind = "event";
                payload->name = "end-file";
                payload->value = reason;
                QueueEvent(payload);
                break;
            }
            case MPV_EVENT_START_FILE:
            case MPV_EVENT_IDLE:
            case MPV_EVENT_FILE_LOADED: {
                auto *payload = new EventPayload();
                payload->kind = "event";
                payload->name = mpv_event_name(ev->event_id);
                QueueEvent(payload);
                break;
            }
            case MPV_EVENT_SHUTDOWN: {
                auto *payload = new EventPayload();
                payload->kind = "event";
                payload->name = "shutdown";
                QueueEvent(payload);
                g_running.store(false);
                break;
            }
            default:
                break;
        }
    }
}

napi_value JsString(napi_env env, const std::string &value) {
    napi_value result = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.size(), &result);
    return result;
}

void TsfCallback(napi_env env, napi_value jsCallback, void *context, void *data) {
    auto *payload = static_cast<EventPayload *>(data);
    if (payload == nullptr) {
        return;
    }
    napi_value global = nullptr;
    napi_value event = nullptr;
    napi_get_global(env, &global);
    napi_create_object(env, &event);
    napi_value kind = JsString(env, payload->kind);
    napi_value name = JsString(env, payload->name);
    napi_value value = JsString(env, payload->value);
    napi_value text = JsString(env, payload->text);
    napi_value genVal = nullptr;
    napi_create_int32(env, payload->gen, &genVal);
    napi_set_named_property(env, event, "kind", kind);
    napi_set_named_property(env, event, "name", name);
    napi_set_named_property(env, event, "value", value);
    napi_set_named_property(env, event, "text", text);
    napi_set_named_property(env, event, "gen", genVal);
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    napi_call_function(env, global, jsCallback, 1, &event, nullptr);
    delete payload;
}

napi_value SetEventCallback(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return nullptr;
    }
    if (g_callbackSet.load()) {
        napi_release_threadsafe_function(g_tsf, napi_tsfn_abort);
        g_callbackSet.store(false);
    }
    napi_value resource_name = nullptr;
    napi_create_string_utf8(env, "mpvEvent", NAPI_AUTO_LENGTH, &resource_name);
    napi_create_threadsafe_function(env, args[0], nullptr, resource_name, 0, 1, nullptr,
                                    nullptr, nullptr, TsfCallback, &g_tsf);
    g_callbackSet.store(true);
    return nullptr;
}

napi_value Init(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1 || g_mpv != nullptr) {
        return nullptr;
    }
    char surfaceId[128] = {0};
    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], surfaceId, sizeof(surfaceId), &len);
    double surfaceWidth = 0;
    double surfaceHeight = 0;
    if (argc >= 3 && args[1] != nullptr && args[2] != nullptr) {
        napi_get_value_double(env, args[1], &surfaceWidth);
        napi_get_value_double(env, args[2], &surfaceHeight);
    }
    if (surfaceWidth < 16 || surfaceHeight < 16) {
        // mpv needs a non-zero buffer geometry before the first reconfig,
        // otherwise the ohos VO fails with "Failed to get height and width"
        // (integration README section 5).
        surfaceWidth = 1920;
        surfaceHeight = 1080;
    }

    g_mpv = mpv_create();
    if (g_mpv == nullptr) {
        LogMpv(LOG_ERROR, "mpv_create failed");
        return nullptr;
    }
    mpv_set_option_string(g_mpv, "wid", surfaceId);
    mpv_set_option_string(g_mpv, "vo", "gpu-next");
    mpv_set_option_string(g_mpv, "gpu-context", "ohosvk");
    mpv_set_option_string(g_mpv, "gpu-api", "vulkan");
    mpv_set_option_string(g_mpv, "hwdec", "ohcodec");
    mpv_set_option_string(g_mpv, "hwdec-software-fallback", "3");
    mpv_set_option_string(g_mpv, "force-window", "yes");
    mpv_set_option_string(g_mpv, "keep-open", "yes");
    mpv_set_option_string(g_mpv, "idle", "yes");
    mpv_set_option_string(g_mpv, "input-default-bindings", "no");
    mpv_set_option_string(g_mpv, "input-vo-keyboard", "no");
    mpv_set_option_string(g_mpv, "terminal", "no");

    OHNativeWindow *window = nullptr;
    if (surfaceId[0] != '\0') {
        uint64_t sid = strtoull(surfaceId, nullptr, 10);
        int32_t ret = OH_NativeWindow_CreateNativeWindowFromSurfaceId(sid, &window);
        OH_LOG_Print(static_cast<LogType>(LOG_APP), LOG_INFO, LOG_DOMAIN, LOG_TAG,
                     "CreateNativeWindowFromSurfaceId(%{public}llu) ret=%{public}d", (unsigned long long)sid, ret);
        g_nativeWindow = window;
        if (ret == 0 && g_nativeWindow != nullptr) {
            int32_t geo = OH_NativeWindow_NativeWindowHandleOpt(
                g_nativeWindow, SET_BUFFER_GEOMETRY,
                static_cast<int32_t>(surfaceWidth), static_cast<int32_t>(surfaceHeight));
            if (geo == 0) {
                g_geoW = static_cast<int32_t>(surfaceWidth);
                g_geoH = static_cast<int32_t>(surfaceHeight);
            }
            OH_LOG_Print(static_cast<LogType>(LOG_APP), LOG_INFO, LOG_DOMAIN, LOG_TAG,
                         "initial SET_BUFFER_GEOMETRY ret=%{public}d", geo);
        }
    }

    int error = mpv_initialize(g_mpv);
    if (error < 0) {
        LogMpv(LOG_ERROR, mpv_error_string(error));
        mpv_terminate_destroy(g_mpv);
        g_mpv = nullptr;
        return nullptr;
    }
    // Written as a property after initialize, matching the timing in
    // integration README section 5 (never before mpv_initialize).
    char surfaceSizeOpt[64] = {0};
    snprintf(surfaceSizeOpt, sizeof(surfaceSizeOpt), "%.0fx%.0f", surfaceWidth, surfaceHeight);
    mpv_set_property_string(g_mpv, "ohos-surface-size", surfaceSizeOpt);
    mpv_request_log_messages(g_mpv, "debug");
    const char *observed[] = {
        "pause", "core-idle", "paused-for-cache", "eof-reached",
        "cache-buffering-state", "hwdec-current", "video-codec",
        "video-format", "estimated-vf-fps", "frame-drop-count",
        "decoder-frame-drop-count", "video-out-params",
        "time-pos", "demuxer-cache-time", "width", "height", "paused",
    };
    for (const char *name : observed) {
        mpv_observe_property(g_mpv, 0, name, MPV_FORMAT_STRING);
    }

    g_running.store(true);
    g_eventThread = std::thread(EventLoop);
    LogMpv(LOG_INFO, "mpv initialized");
    return nullptr;
}

napi_value LoadFile(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1 || g_mpv == nullptr) {
        return nullptr;
    }
    char url[4096] = {0};
    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], url, sizeof(url), &len);
    if (argc >= 2) {
        char headers[4096] = {0};
        napi_get_value_string_utf8(env, args[1], headers, sizeof(headers), &len);
        if (headers[0] != '\0') {
            // Comma separated "Key: Value" pairs (integration README 6.2).
            mpv_set_property_string(g_mpv, "http-header-fields", headers);
        }
    }
    if (argc >= 3 && args[2] != nullptr) {
        double gen = 0;
        napi_get_value_double(env, args[2], &gen);
        g_eventGeneration.store(static_cast<int32_t>(gen));
    }
    std::string cmd = std::string("loadfile ") + url + " replace";
    int error = mpv_command_string(g_mpv, cmd.c_str());
    LogMpv(error < 0 ? LOG_ERROR : LOG_INFO, cmd.c_str());
    return nullptr;
}

struct PropertyWork {
    napi_async_work work = nullptr;
    std::string name;
    std::string value;
};

void SetPropertyExecute(napi_env env, void *data) {
    auto *work = static_cast<PropertyWork *>(data);
    if (g_mpv != nullptr) {
        mpv_set_property_string(g_mpv, work->name.c_str(), work->value.c_str());
    }
}

void SetPropertyComplete(napi_env env, napi_status status, void *data) {
    auto *work = static_cast<PropertyWork *>(data);
    napi_delete_async_work(env, work->work);
    delete work;
}

napi_value SetPropertyString(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2 || g_mpv == nullptr) {
        return nullptr;
    }
    auto *work = new PropertyWork();
    size_t len = 0;
    char name[256] = {0};
    napi_get_value_string_utf8(env, args[0], name, sizeof(name), &len);
    work->name = name;
    char value[4096] = {0};
    napi_get_value_string_utf8(env, args[1], value, sizeof(value), &len);
    work->value = value;

    napi_value resource_name = nullptr;
    napi_create_string_utf8(env, "mpvSetProperty", NAPI_AUTO_LENGTH, &resource_name);
    napi_create_async_work(env, nullptr, resource_name, SetPropertyExecute,
                           SetPropertyComplete, work, &work->work);
    napi_queue_async_work(env, work->work);
    return nullptr;
}

napi_value GetPropertyString(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1 || g_mpv == nullptr) {
        return nullptr;
    }
    char name[256] = {0};
    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], name, sizeof(name), &len);
    char *value = mpv_get_property_string(g_mpv, name);
    napi_value result = JsString(env, value != nullptr ? value : "");
    mpv_free(value);
    return result;
}

napi_value CommandString(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1 || g_mpv == nullptr) {
        return nullptr;
    }
    char cmd[4096] = {0};
    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], cmd, sizeof(cmd), &len);
    mpv_command_string(g_mpv, cmd);
    return nullptr;
}

napi_value Destroy(napi_env env, napi_callback_info info) {
    if (g_mpv == nullptr) {
        return nullptr;
    }
    g_running.store(false);
    mpv_wakeup(g_mpv);
    if (g_eventThread.joinable()) {
        g_eventThread.join();
    }
    mpv_terminate_destroy(g_mpv);
    g_mpv = nullptr;
    if (g_nativeWindow != nullptr) {
        OH_NativeWindow_DestroyNativeWindow(g_nativeWindow);
        g_nativeWindow = nullptr;
    }
    LogMpv(LOG_INFO, "mpv destroyed");
    return nullptr;
}

napi_value InitModule(napi_env env, napi_value exports) {
    const napi_property_descriptor props[] = {
        {"setEventCallback", nullptr, SetEventCallback, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"init", nullptr, Init, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"loadFile", nullptr, LoadFile, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setPropertyString", nullptr, SetPropertyString, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getPropertyString", nullptr, GetPropertyString, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"commandString", nullptr, CommandString, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setGeometry", nullptr, SetGeometry, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"destroy", nullptr, Destroy, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(props) / sizeof(props[0]), props);
    return exports;
}

napi_module g_mpvModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = InitModule,
    .nm_modname = "mpv_napi",
    .nm_priv = nullptr,
    .reserved = {0},
};

} // namespace

extern "C" __attribute__((constructor)) void RegisterMpvNapiModule(void) {
    napi_module_register(&g_mpvModule);
}
