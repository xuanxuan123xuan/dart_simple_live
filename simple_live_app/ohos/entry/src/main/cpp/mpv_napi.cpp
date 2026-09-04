// Milestone 0 verification bridge: libmpv -> Flutter SurfaceTextureEntry.
//
// Threading rules from integration README section 4:
//  - a dedicated thread pumps mpv_wait_event and hands events to ArkTS via
//    napi_threadsafe_function (never touch napi from mpv callback context);
//  - property writes are async (sync writes from the UI thread hit XCollie).
#include <atomic>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <mutex>
#include <string>
#include <utility>
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

std::atomic<bool> g_running{false};
std::atomic<bool> g_callbackSet{false};
std::atomic<mpv_handle *> g_mpv{nullptr};
std::thread g_eventThread;
napi_threadsafe_function g_tsf = nullptr;
std::mutex g_callbackMutex;
std::atomic<OHNativeWindow *> g_nativeWindow{nullptr};

enum class CommandType {
    LOAD_FILE,
    SET_PROPERTY,
    COMMAND,
    SET_GEOMETRY,
};

struct MpvCommand {
    CommandType type;
    std::string name;
    std::string value;
    std::string url;
    std::string headers;
    std::string command;
    int32_t generation = 0;
    int32_t width = 0;
    int32_t height = 0;
};

std::mutex g_commandMutex;
std::condition_variable g_commandCv;
std::deque<MpvCommand> g_commandQueue;
bool g_commandStopping = false;
bool g_commandAccepting = false;
std::thread g_commandThread;

std::mutex g_generationMutex;
std::deque<int32_t> g_pendingGenerations;
std::atomic<int32_t> g_activeGeneration{0};
std::atomic<bool> g_activePlayback{false};
std::atomic<int32_t> g_videoGeometryGeneration{-1};
std::atomic<int32_t> g_framePresentedGeneration{-1};

void LogMpv(int priority, const char *msg) {
    OH_LOG_Print(static_cast<LogType>(LOG_APP), static_cast<LogLevel>(priority), LOG_DOMAIN, LOG_TAG, "%{public}s", msg);
}

bool QueueEvent(EventPayload *payload, int32_t generation = -1) {
    std::lock_guard<std::mutex> lock(g_callbackMutex);
    if (!g_callbackSet.load() || g_tsf == nullptr) {
        delete payload;
        return false;
    }
    payload->gen = generation >= 0 ? generation : g_activeGeneration.load();
    // Payload ownership transfers to the TSF callback on success.
    const napi_status status = napi_call_threadsafe_function(g_tsf, payload, napi_tsfn_nonblocking);
    if (status != napi_ok) {
        delete payload;
        return false;
    }
    return true;
}

std::atomic<int32_t> g_geoW{0};
std::atomic<int32_t> g_geoH{0};

void RemovePendingGeneration(int32_t generation) {
    std::lock_guard<std::mutex> lock(g_generationMutex);
    for (auto it = g_pendingGenerations.begin(); it != g_pendingGenerations.end(); ++it) {
        if (*it == generation) {
            g_pendingGenerations.erase(it);
            return;
        }
    }
}

void ClearPendingGenerations() {
    std::lock_guard<std::mutex> lock(g_generationMutex);
    g_pendingGenerations.clear();
}

int32_t ActivateNextGeneration() {
    const int32_t previous = g_activeGeneration.load();
    int32_t next = previous;
    {
        std::lock_guard<std::mutex> lock(g_generationMutex);
        if (!g_pendingGenerations.empty()) {
            next = g_pendingGenerations.front();
            g_pendingGenerations.pop_front();
        }
    }
    g_activeGeneration.store(next);
    if (next != previous) {
        g_framePresentedGeneration.store(-1);
    }
    return next;
}

void ExecuteCommand(const MpvCommand &command) {
    mpv_handle *mpv = g_mpv.load();
    if (mpv == nullptr) {
        return;
    }
    switch (command.type) {
        case CommandType::LOAD_FILE: {
            {
                std::lock_guard<std::mutex> lock(g_generationMutex);
                g_pendingGenerations.push_back(command.generation);
            }
            // Apply request-scoped headers immediately before loadfile so the
            // command queue preserves the same order as Dart's calls. An
            // empty value also clears headers from the previous stream.
            mpv_set_property_string(mpv, "http-header-fields", command.headers.c_str());
            const char *args[] = {
                "loadfile",
                command.url.c_str(),
                "replace",
                nullptr,
            };
            const int error = mpv_command(mpv, args);
            if (error < 0) {
                RemovePendingGeneration(command.generation);
            }
            OH_LOG_Print(static_cast<LogType>(LOG_APP),
                         error < 0 ? LOG_ERROR : LOG_INFO,
                         LOG_DOMAIN,
                         LOG_TAG,
                         "loadFile stage=command gen=%{public}d status=%{public}d urlLength=%{public}zu headers=%{public}s",
                         command.generation,
                         error,
                         command.url.size(),
                         command.headers.empty() ? "empty" : "present");
            break;
        }
        case CommandType::SET_PROPERTY:
            mpv_set_property_string(mpv, command.name.c_str(), command.value.c_str());
            break;
        case CommandType::COMMAND: {
            mpv_command_string(mpv, command.command.c_str());
            if (command.command == "stop") {
                ClearPendingGenerations();
            }
            break;
        }
        case CommandType::SET_GEOMETRY: {
            OHNativeWindow *window = g_nativeWindow.load();
            if (window == nullptr) {
                break;
            }
            const int32_t code = OH_NativeWindow_NativeWindowHandleOpt(
                window,
                SET_BUFFER_GEOMETRY,
                command.width,
                command.height);
            if (code == 0) {
                g_geoW.store(command.width);
                g_geoH.store(command.height);
            }
            OH_LOG_Print(static_cast<LogType>(LOG_APP), LOG_INFO, LOG_DOMAIN, LOG_TAG,
                         "setGeometry stage=command size=%{public}dx%{public}d code=%{public}d",
                         command.width,
                         command.height,
                         code);
            break;
        }
    }
}

void CommandLoop() {
    while (true) {
        MpvCommand command;
        {
            std::unique_lock<std::mutex> lock(g_commandMutex);
            g_commandCv.wait(lock, [] {
                return g_commandStopping || !g_commandQueue.empty();
            });
            if (g_commandQueue.empty() && g_commandStopping) {
                break;
            }
            command = std::move(g_commandQueue.front());
            g_commandQueue.pop_front();
        }
        ExecuteCommand(command);
    }
}

bool QueueCommand(MpvCommand command) {
    if (g_mpv.load() == nullptr) {
        return false;
    }
    {
        std::lock_guard<std::mutex> lock(g_commandMutex);
        if (!g_commandAccepting || g_commandStopping) {
            return false;
        }
        g_commandQueue.emplace_back(std::move(command));
    }
    g_commandCv.notify_one();
    return true;
}

// Lightweight: never touches mpv state (a synchronous vo teardown here
// blocked the event pump and caused black-frame loops). Only notifies Dart,
// which owns the full vo hot-reconfig sequence via async method calls.
void HandleNativeWindowGeometry(int width, int height) {
    if (width <= 0 || height <= 0) {
        return;
    }
    if (width == g_geoW.load() && height == g_geoH.load()) {
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
    if (argc < 2 || g_mpv.load() == nullptr || g_nativeWindow.load() == nullptr) {
        return nullptr;
    }
    double w = 0;
    double h = 0;
    napi_get_value_double(env, args[0], &w);
    napi_get_value_double(env, args[1], &h);
    if (w < 16 || h < 16) {
        return nullptr;
    }
    MpvCommand command;
    command.type = CommandType::SET_GEOMETRY;
    command.width = static_cast<int32_t>(w);
    command.height = static_cast<int32_t>(h);
    QueueCommand(std::move(command));
    return nullptr;
}

std::atomic<int64_t> g_lastTimePosPushMs{0};
std::atomic<int64_t> g_lastCachePushMs{0};

void EventLoop() {
    while (g_running.load()) {
        mpv_handle *mpv = g_mpv.load();
        if (mpv == nullptr) {
            break;
        }
        mpv_event *ev = mpv_wait_event(mpv, 0.25);
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
                    if (mpv_get_property(mpv, "video-out-params/dw", MPV_FORMAT_INT64, &dw) >= 0 &&
                        mpv_get_property(mpv, "video-out-params/dh", MPV_FORMAT_INT64, &dh) >= 0 &&
                        dw > 0 && dh > 0) {
                        g_videoGeometryGeneration.store(g_activeGeneration.load());
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
                payload->name = msg->prefix != nullptr ? msg->prefix : "mpv";
                // mpv's diagnostic text can contain stream URLs or request
                // headers. Keep the channel useful for severity filtering
                // without forwarding those secrets to Dart logs.
                payload->text = msg->level != nullptr ? msg->level : "";
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
                g_activePlayback.store(false);
                auto *payload = new EventPayload();
                payload->kind = "event";
                payload->name = "end-file";
                payload->value = reason;
                QueueEvent(payload);
                break;
            }
            case MPV_EVENT_START_FILE: {
                const int32_t generation = ActivateNextGeneration();
                g_videoGeometryGeneration.store(-1);
                g_activePlayback.store(generation > 0);
                auto *payload = new EventPayload();
                payload->kind = "event";
                payload->name = "start-file";
                QueueEvent(payload, generation);
                break;
            }
#if MPV_ENABLE_DEPRECATED
            case MPV_EVENT_TICK: {
                const int32_t generation = g_activeGeneration.load();
                if (generation <= 0 ||
                    !g_activePlayback.load() ||
                    g_videoGeometryGeneration.load() != generation) {
                    break;
                }
                int32_t expected = g_framePresentedGeneration.load();
                if (expected == generation ||
                    !g_framePresentedGeneration.compare_exchange_strong(expected, generation)) {
                    break;
                }
                auto *payload = new EventPayload();
                payload->kind = "event";
                payload->name = "video-frame-presented";
                if (!QueueEvent(payload, generation)) {
                    int32_t marked = generation;
                    g_framePresentedGeneration.compare_exchange_strong(marked, -1);
                }
                break;
            }
#endif
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
    std::lock_guard<std::mutex> lock(g_callbackMutex);
    if (g_callbackSet.load()) {
        napi_release_threadsafe_function(g_tsf, napi_tsfn_abort);
        g_callbackSet.store(false);
        g_tsf = nullptr;
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
    if (argc < 1 || g_mpv.load() != nullptr) {
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

    mpv_handle *mpv = mpv_create();
    if (mpv == nullptr) {
        LogMpv(LOG_ERROR, "mpv_create failed");
        return nullptr;
    }
    g_mpv.store(mpv);
    mpv_set_option_string(mpv, "wid", surfaceId);
    mpv_set_option_string(mpv, "vo", "gpu-next");
    mpv_set_option_string(mpv, "gpu-context", "ohosvk");
    mpv_set_option_string(mpv, "gpu-api", "vulkan");
    mpv_set_option_string(mpv, "hwdec", "ohcodec");
    mpv_set_option_string(mpv, "hwdec-software-fallback", "3");
    // Keep the two playback profiles on the same A/V clock baseline. Dart
    // may add profile-specific options later, but both paths must start with
    // mpv's audio clock and initial sync enabled.
    mpv_set_option_string(mpv, "video-sync", "audio");
    mpv_set_option_string(mpv, "initial-audio-sync", "yes");
    mpv_set_option_string(mpv, "force-window", "yes");
    mpv_set_option_string(mpv, "keep-open", "yes");
    mpv_set_option_string(mpv, "idle", "yes");
    mpv_set_option_string(mpv, "input-default-bindings", "no");
    mpv_set_option_string(mpv, "input-vo-keyboard", "no");
    mpv_set_option_string(mpv, "terminal", "no");

    OHNativeWindow *window = nullptr;
    if (surfaceId[0] != '\0') {
        uint64_t sid = strtoull(surfaceId, nullptr, 10);
        int32_t ret = OH_NativeWindow_CreateNativeWindowFromSurfaceId(sid, &window);
        OH_LOG_Print(static_cast<LogType>(LOG_APP), LOG_INFO, LOG_DOMAIN, LOG_TAG,
                     "CreateNativeWindowFromSurfaceId(%{public}llu) ret=%{public}d", (unsigned long long)sid, ret);
        g_nativeWindow.store(window);
        if (ret == 0 && window != nullptr) {
            int32_t geo = OH_NativeWindow_NativeWindowHandleOpt(
                window, SET_BUFFER_GEOMETRY,
                static_cast<int32_t>(surfaceWidth), static_cast<int32_t>(surfaceHeight));
            if (geo == 0) {
                g_geoW.store(static_cast<int32_t>(surfaceWidth));
                g_geoH.store(static_cast<int32_t>(surfaceHeight));
            }
            OH_LOG_Print(static_cast<LogType>(LOG_APP), LOG_INFO, LOG_DOMAIN, LOG_TAG,
                         "initial SET_BUFFER_GEOMETRY ret=%{public}d", geo);
        }
    }

    int error = mpv_initialize(mpv);
    if (error < 0) {
        LogMpv(LOG_ERROR, mpv_error_string(error));
        mpv_terminate_destroy(mpv);
        g_mpv.store(nullptr);
        return nullptr;
    }
    // Written as a property after initialize, matching the timing in
    // integration README section 5 (never before mpv_initialize).
    char surfaceSizeOpt[64] = {0};
    snprintf(surfaceSizeOpt, sizeof(surfaceSizeOpt), "%.0fx%.0f", surfaceWidth, surfaceHeight);
    mpv_set_property_string(mpv, "ohos-surface-size", surfaceSizeOpt);
    mpv_request_log_messages(mpv, "warn");
#if MPV_ENABLE_DEPRECATED
    const int tickError = mpv_request_event(mpv, MPV_EVENT_TICK, 1);
    if (tickError < 0) {
        OH_LOG_Print(static_cast<LogType>(LOG_APP), LOG_WARN, LOG_DOMAIN, LOG_TAG,
                     "mpv tick event unavailable code=%{public}d", tickError);
    }
#endif
    const char *observed[] = {
        "pause", "core-idle", "paused-for-cache", "eof-reached",
        "cache-buffering-state", "hwdec-current", "video-codec",
        "video-format", "estimated-vf-fps", "frame-drop-count",
        "decoder-frame-drop-count", "video-out-params",
        "time-pos", "demuxer-cache-time", "width", "height", "paused",
    };
    for (const char *name : observed) {
        mpv_observe_property(mpv, 0, name, MPV_FORMAT_STRING);
    }

    ClearPendingGenerations();
    g_activeGeneration.store(0);
    g_activePlayback.store(false);
    g_videoGeometryGeneration.store(-1);
    g_framePresentedGeneration.store(-1);
    {
        std::lock_guard<std::mutex> lock(g_commandMutex);
        g_commandQueue.clear();
        g_commandStopping = false;
        g_commandAccepting = true;
    }
    g_commandThread = std::thread(CommandLoop);
    g_running.store(true);
    g_eventThread = std::thread(EventLoop);
    LogMpv(LOG_INFO, "mpv initialized");
    return nullptr;
}

napi_value LoadFile(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1 || g_mpv.load() == nullptr) {
        return nullptr;
    }
    char url[4096] = {0};
    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], url, sizeof(url), &len);
    std::string headersValue;
    if (argc >= 2) {
        char headers[4096] = {0};
        napi_get_value_string_utf8(env, args[1], headers, sizeof(headers), &len);
        headersValue = headers;
    }
    int32_t generation = 0;
    if (argc >= 3 && args[2] != nullptr) {
        double gen = 0;
        napi_get_value_double(env, args[2], &gen);
        generation = static_cast<int32_t>(gen);
    }
    MpvCommand command;
    command.type = CommandType::LOAD_FILE;
    command.url = url;
    command.headers = std::move(headersValue);
    command.generation = generation;
    QueueCommand(std::move(command));
    return nullptr;
}

napi_value SetPropertyString(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2 || g_mpv.load() == nullptr) {
        return nullptr;
    }
    size_t len = 0;
    char name[256] = {0};
    napi_get_value_string_utf8(env, args[0], name, sizeof(name), &len);
    char value[4096] = {0};
    napi_get_value_string_utf8(env, args[1], value, sizeof(value), &len);
    MpvCommand command;
    command.type = CommandType::SET_PROPERTY;
    command.name = name;
    command.value = value;
    QueueCommand(std::move(command));
    return nullptr;
}

napi_value GetPropertyString(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1 || g_mpv.load() == nullptr) {
        return nullptr;
    }
    char name[256] = {0};
    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], name, sizeof(name), &len);
    char *value = mpv_get_property_string(g_mpv.load(), name);
    napi_value result = JsString(env, value != nullptr ? value : "");
    mpv_free(value);
    return result;
}

napi_value CommandString(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1 || g_mpv.load() == nullptr) {
        return nullptr;
    }
    char cmd[4096] = {0};
    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], cmd, sizeof(cmd), &len);
    MpvCommand command;
    command.type = CommandType::COMMAND;
    command.command = cmd;
    QueueCommand(std::move(command));
    return nullptr;
}

napi_value Destroy(napi_env env, napi_callback_info info) {
    mpv_handle *mpv = g_mpv.load();
    if (mpv == nullptr) {
        return nullptr;
    }
    g_running.store(false);
    mpv_wakeup(mpv);
    if (g_eventThread.joinable()) {
        g_eventThread.join();
    }
    {
        std::lock_guard<std::mutex> lock(g_commandMutex);
        g_commandAccepting = false;
        g_commandStopping = true;
    }
    g_commandCv.notify_all();
    if (g_commandThread.joinable()) {
        g_commandThread.join();
    }
    mpv_terminate_destroy(mpv);
    g_mpv.store(nullptr);
    OHNativeWindow *window = g_nativeWindow.exchange(nullptr);
    if (window != nullptr) {
        OH_NativeWindow_DestroyNativeWindow(window);
    }
    ClearPendingGenerations();
    g_activeGeneration.store(0);
    g_activePlayback.store(false);
    g_videoGeometryGeneration.store(-1);
    g_framePresentedGeneration.store(-1);
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
