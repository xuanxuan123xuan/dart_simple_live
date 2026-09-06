// Milestone 0 verification bridge: libmpv -> Flutter SurfaceTextureEntry.
//
// Threading rules from integration README section 4:
//  - a dedicated thread pumps mpv_wait_event and hands events to ArkTS via
//    napi_threadsafe_function (never touch napi from mpv callback context);
//  - property writes are async (sync writes from the UI thread hit XCollie).
#include <atomic>
#include <algorithm>
#include <cctype>
#include <condition_variable>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>
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
    std::string level;
    std::string category;
    int32_t gen = 0;
    int32_t code = 0;
};

// These bridge-local errors are kept outside mpv's negative error range. They
// are delivered through rejected JS promises, so callers can distinguish a
// superseded controller from an mpv failure without parsing log text.
constexpr int32_t kBridgeClosed = -10001;
constexpr int32_t kInvalidArgument = -10002;
constexpr int32_t kStaleGeneration = -10003;
constexpr int32_t kNativeWindowFailure = -10004;

struct Completion {
    void Complete(int32_t error, std::string detail) {
        {
            std::lock_guard<std::mutex> lock(mutex);
            if (done) {
                return;
            }
            done = true;
            this->error = error;
            this->detail = std::move(detail);
        }
        cv.notify_all();
    }

    int32_t Wait(std::string *detailOut) {
        std::unique_lock<std::mutex> lock(mutex);
        cv.wait(lock, [this] { return done; });
        if (detailOut != nullptr) {
            *detailOut = detail;
        }
        return error;
    }

private:
    std::mutex mutex;
    std::condition_variable cv;
    bool done = false;
    int32_t error = 0;
    std::string detail;
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
    RECONFIGURE_SURFACE,
    SWITCH_SURFACE,
};

struct MpvCommand {
    CommandType type;
    std::string name;
    std::string value;
    std::string url;
    std::string headers;
    std::string command;
    std::string surfaceId;
    int32_t generation = 0;
    int32_t width = 0;
    int32_t height = 0;
    std::shared_ptr<Completion> completion;
};

// mpv_set_property_async()/mpv_command_async() replies are consumed by the
// event-pump thread. The command worker waits on this small native primitive,
// which keeps NAPI and mpv calls off the ArkTS/UI thread while still exposing
// actual mpv errors to the JS Promise returned by the bridge.
struct MpvReply {
    std::shared_ptr<Completion> completion = std::make_shared<Completion>();
};

std::mutex g_commandMutex;
std::condition_variable g_commandCv;
// The surface id mpv is currently bound to via `wid`. Kept in sync by Init and
// SwitchSurface so SET_GEOMETRY can re-bind `wid` after a buffer-geometry flip
// (portrait <-> landscape) without Dart having to resend it every time.
std::mutex g_surfaceIdMutex;
std::string g_surfaceId;
std::deque<MpvCommand> g_commandQueue;
bool g_commandStopping = false;
bool g_commandAccepting = false;
std::thread g_commandThread;

std::atomic<uint64_t> g_nextReplyId{1};
std::mutex g_replyMutex;
bool g_repliesClosed = true;
std::unordered_map<uint64_t, std::shared_ptr<MpvReply>> g_pendingReplies;

std::mutex g_generationMutex;
std::deque<int32_t> g_pendingGenerations;
std::atomic<int32_t> g_activeGeneration{0};
std::atomic<int32_t> g_latestRequestedGeneration{0};
std::atomic<bool> g_activePlayback{false};
std::atomic<int32_t> g_framePresentedGeneration{-1};
std::atomic<int32_t> g_videoWidth{0};
std::atomic<int32_t> g_videoHeight{0};
std::atomic<bool> g_fileLoaded{false};
std::atomic<bool> g_coreIdle{true};

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

struct OperationResult {
    int32_t error = 0;
    std::string detail;
};

std::string MpvErrorText(int32_t error) {
    const char *text = mpv_error_string(error);
    return text != nullptr ? text : "mpv operation failed";
}

OperationResult Success() {
    return {};
}

OperationResult Failure(int32_t error, std::string detail = {}) {
    if (detail.empty() && error < 0 && error > -10000) {
        detail = MpvErrorText(error);
    }
    if (detail.empty()) {
        detail = "native mpv bridge operation failed";
    }
    return {error, std::move(detail)};
}

void CompleteCommand(const MpvCommand &command, const OperationResult &result) {
    if (command.completion != nullptr) {
        command.completion->Complete(result.error, result.detail);
    }
}

uint64_t ReserveMpvReply(const std::shared_ptr<MpvReply> &reply) {
    uint64_t id = g_nextReplyId.fetch_add(1);
    if (id == 0) {
        id = g_nextReplyId.fetch_add(1);
    }
    std::lock_guard<std::mutex> lock(g_replyMutex);
    if (g_repliesClosed) {
        return 0;
    }
    g_pendingReplies.emplace(id, reply);
    return id;
}

std::shared_ptr<MpvReply> TakeMpvReply(uint64_t id) {
    std::lock_guard<std::mutex> lock(g_replyMutex);
    auto it = g_pendingReplies.find(id);
    if (it == g_pendingReplies.end()) {
        return nullptr;
    }
    auto reply = it->second;
    g_pendingReplies.erase(it);
    return reply;
}

void CompleteMpvReply(uint64_t id, int32_t error, std::string detail = {}) {
    auto reply = TakeMpvReply(id);
    if (reply != nullptr) {
        reply->completion->Complete(error, std::move(detail));
    }
}

void FailMpvReplies(int32_t error, const char *detail) {
    std::vector<std::shared_ptr<MpvReply>> replies;
    {
        std::lock_guard<std::mutex> lock(g_replyMutex);
        g_repliesClosed = true;
        replies.reserve(g_pendingReplies.size());
        for (auto &entry : g_pendingReplies) {
            replies.emplace_back(std::move(entry.second));
        }
        g_pendingReplies.clear();
    }
    for (const auto &reply : replies) {
        reply->completion->Complete(error, detail != nullptr ? detail : "mpv bridge closed");
    }
}

OperationResult WaitForReply(const std::shared_ptr<MpvReply> &reply) {
    std::string detail;
    const int32_t error = reply->completion->Wait(&detail);
    return error < 0 ? Failure(error, std::move(detail)) : Success();
}

OperationResult SetPropertyOnMpv(mpv_handle *mpv, const std::string &name,
                                 const std::string &value) {
    if (mpv == nullptr) {
        return Failure(kBridgeClosed, "mpv bridge is not initialized");
    }
    auto reply = std::make_shared<MpvReply>();
    const uint64_t replyId = ReserveMpvReply(reply);
    if (replyId == 0) {
        return Failure(kBridgeClosed, "mpv reply channel is closed");
    }
    // MPV_FORMAT_STRING expects a `char**` (the address of a char* variable),
    // not a `char*`. mpv copies the string synchronously inside the call (see
    // client.h: "The value will be copied by the function"), so the local
    // buffer is safe to free on return; only the reply is delivered async.
    // Passing `&mutableValue[0]` (a char*) here made mpv reinterpret the first
    // 8 bytes of the string as a pointer and dereference it -> native crash
    // right after the stream URL was resolved.
    const char *cstr = value.c_str();
    const int error = mpv_set_property_async(
        mpv, replyId, name.c_str(), MPV_FORMAT_STRING, &cstr);
    if (error < 0) {
        CompleteMpvReply(replyId, error, MpvErrorText(error));
        return WaitForReply(reply);
    }
    return WaitForReply(reply);
}

OperationResult CommandOnMpv(mpv_handle *mpv, const std::string &command) {
    if (mpv == nullptr) {
        return Failure(kBridgeClosed, "mpv bridge is not initialized");
    }
    // commandString supports the same input.conf-style parsing that callers
    // already use. It is executed on the dedicated command thread, so the
    // synchronous API does not block the ArkTS/UI thread.
    const int error = mpv_command_string(mpv, command.c_str());
    return error < 0 ? Failure(error) : Success();
}

OperationResult LoadFileOnMpv(mpv_handle *mpv, const std::string &url) {
    if (mpv == nullptr) {
        return Failure(kBridgeClosed, "mpv bridge is not initialized");
    }
    auto reply = std::make_shared<MpvReply>();
    const uint64_t replyId = ReserveMpvReply(reply);
    if (replyId == 0) {
        return Failure(kBridgeClosed, "mpv reply channel is closed");
    }
    const char *args[] = {"loadfile", url.c_str(), "replace", nullptr};
    const int error = mpv_command_async(mpv, replyId, args);
    if (error < 0) {
        CompleteMpvReply(replyId, error, MpvErrorText(error));
        return WaitForReply(reply);
    }
    return WaitForReply(reply);
}

bool IsStaleGeneration(const MpvCommand &command) {
    if (command.generation <= 0) {
        return false;
    }
    const int32_t active = g_activeGeneration.load();
    const int32_t latest = g_latestRequestedGeneration.load();
    return (active > 0 && command.generation < active) ||
           (latest > 0 && command.generation < latest);
}

OperationResult StaleResult(const MpvCommand &command) {
    OH_LOG_Print(static_cast<LogType>(LOG_APP), LOG_WARN,
                 LOG_DOMAIN, LOG_TAG,
                 "command skipped stale generation=%{public}d active=%{public}d latest=%{public}d",
                 command.generation, g_activeGeneration.load(),
                 g_latestRequestedGeneration.load());
    return Failure(kStaleGeneration, "stale playback generation");
}

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

std::string ReadPropertyString(mpv_handle *mpv, const char *name) {
    char *value = mpv_get_property_string(mpv, name);
    std::string result = value != nullptr ? value : "";
    mpv_free(value);
    return result;
}

std::string ReadActiveHwdec(mpv_handle *mpv) {
    const std::string current = ReadPropertyString(mpv, "hwdec-current");
    // Before the first file is loaded mpv reports hwdec-current=no even when
    // the requested hwdec mode is ohcodec. That is an idle-state observation,
    // not a fallback decision; preserving it through a surface rebuild would
    // silently change the next stream to software decoding.
    if (current.empty() || (current == "no" && !g_fileLoaded.load())) {
        const std::string requested = ReadPropertyString(mpv, "hwdec");
        return requested.empty() ? current : requested;
    }
    return current;
}

// Restore the state that was visible before a surface transaction detached
// the VO. Every write is awaited so this rollback is ordered with the failed
// transaction and leaves no untracked mpv reply behind.
OperationResult RestoreSurfaceState(mpv_handle *mpv, const std::string &oldVo,
                                    const std::string &oldPause,
                                    const std::string &oldSurfaceSize,
                                    const std::string &oldSurfaceId,
                                    const std::string &oldHwdec) {
    OperationResult firstFailure = Success();
    const auto restoreProperty = [&](const char *name, const std::string &value) {
        const OperationResult result = SetPropertyOnMpv(mpv, name, value);
        if (firstFailure.error >= 0 && result.error < 0) {
            firstFailure = result;
        }
    };

    if (!oldSurfaceSize.empty()) {
        restoreProperty("ohos-surface-size", oldSurfaceSize);
    }
    if (!oldSurfaceId.empty()) {
        restoreProperty("wid", oldSurfaceId);
    }
    if (!oldHwdec.empty()) {
        restoreProperty("hwdec", oldHwdec);
    }
    restoreProperty("vo", oldVo.empty() ? "gpu-next" : oldVo);
    if (!oldPause.empty()) {
        restoreProperty("pause", oldPause);
    }
    return firstFailure;
}

// mpv explicitly permits asynchronous calls to be reordered. Keep the
// surface rebuild sequence on the command worker and await each reply before
// issuing the next write. A failed step rolls the VO and pause state back;
// callers can then retry after a transient surface or mpv failure.
OperationResult ApplySurfaceState(mpv_handle *mpv, const std::string &surfaceSize,
                                  const std::string &surfaceId,
                                  const std::string &oldVo,
                                  const std::string &oldPause,
                                  const std::string &oldSurfaceSize,
                                  const std::string &oldSurfaceId,
                                  const std::string &oldHwdec) {
    const auto failAfterDetach = [&](const OperationResult &failure) {
        const OperationResult rollback = RestoreSurfaceState(
            mpv, oldVo, oldPause, oldSurfaceSize, oldSurfaceId, oldHwdec);
        if (rollback.error < 0) {
            OH_LOG_Print(static_cast<LogType>(LOG_APP), LOG_ERROR,
                         LOG_DOMAIN, LOG_TAG,
                         "surface rollback failed code=%{public}d",
                         rollback.error);
        }
        return failure;
    };

    OperationResult result = SetPropertyOnMpv(mpv, "vo", "null");
    if (result.error < 0) {
        return result;
    }
    result = SetPropertyOnMpv(mpv, "ohos-surface-size", surfaceSize);
    if (result.error < 0) {
        return failAfterDetach(result);
    }
    if (!surfaceId.empty()) {
        result = SetPropertyOnMpv(mpv, "wid", surfaceId);
        if (result.error < 0) {
            return failAfterDetach(result);
        }
    }
    if (!oldHwdec.empty()) {
        result = SetPropertyOnMpv(mpv, "hwdec", oldHwdec);
        if (result.error < 0) {
            return failAfterDetach(result);
        }
    }
    result = SetPropertyOnMpv(mpv, "vo", oldVo.empty() ? "gpu-next" : oldVo);
    if (result.error < 0) {
        return failAfterDetach(result);
    }
    if (!oldPause.empty()) {
        result = SetPropertyOnMpv(mpv, "pause", oldPause);
        if (result.error < 0) {
            return failAfterDetach(result);
        }
    }
    return Success();
}

OperationResult ReconfigureSurfaceOnMpv(mpv_handle *mpv, int32_t width,
                                        int32_t height) {
    if (mpv == nullptr) {
        return Failure(kBridgeClosed, "mpv bridge is not initialized");
    }
    OHNativeWindow *window = g_nativeWindow.load();
    std::string surfaceId;
    {
        std::lock_guard<std::mutex> lock(g_surfaceIdMutex);
        surfaceId = g_surfaceId;
    }
    // The output NativeWindow is a plugin-wide singleton, but it can be torn
    // down (e.g. by the OS on surface recreation, or by a room switch racing
    // the shared texture) while g_surfaceId is still valid. If the window is
    // gone but the surface id survives, rebuild it from the id instead of
    // failing the reconfigure — this is the "just entered the room and the
    // surface wasn't ready yet" path that used to surface as a fatal
    // "视频输出尺寸更新失败" on the Dart side.
    if (window == nullptr && !surfaceId.empty()) {
        const uint64_t sid = strtoull(surfaceId.c_str(), nullptr, 10);
        if (sid != 0) {
            OHNativeWindow *rebuilt = nullptr;
            const int32_t createCode =
                OH_NativeWindow_CreateNativeWindowFromSurfaceId(sid, &rebuilt);
            if (createCode == 0 && rebuilt != nullptr) {
                OHNativeWindow *expected = nullptr;
                if (g_nativeWindow.compare_exchange_strong(expected, rebuilt)) {
                    window = rebuilt;
                    OH_LOG_Print(static_cast<LogType>(LOG_APP), LOG_WARN,
                                 LOG_DOMAIN, LOG_TAG,
                                 "reconfigureSurface rebuilt NativeWindow from surfaceId=%{public}s",
                                 surfaceId.c_str());
                } else {
                    // Another thread rebuilt it first; use theirs and drop ours.
                    OH_NativeWindow_DestroyNativeWindow(rebuilt);
                    window = g_nativeWindow.load();
                }
            }
        }
    }
    if (window == nullptr) {
        return Failure(kNativeWindowFailure, "output surface is unavailable");
    }

    // Resize the buffer before telling mpv about it. Repeating this native
    // call is harmless, while the vo rebuild below is reserved for a real
    // geometry change.
    const int32_t geometryCode = OH_NativeWindow_NativeWindowHandleOpt(
        window, SET_BUFFER_GEOMETRY, width, height);
    if (geometryCode != 0) {
        return Failure(kNativeWindowFailure,
                       "SET_BUFFER_GEOMETRY failed: " + std::to_string(geometryCode));
    }
    const int32_t previousWidth = g_geoW.load();
    const int32_t previousHeight = g_geoH.load();
    if (previousWidth == width && previousHeight == height) {
        OH_LOG_Print(static_cast<LogType>(LOG_APP), LOG_INFO, LOG_DOMAIN, LOG_TAG,
                     "reconfigureSurface skipped unchanged size=%{public}dx%{public}d",
                     width, height);
        return Success();
    }

    const std::string oldVo = ReadPropertyString(mpv, "vo");
    const std::string oldHwdec = ReadActiveHwdec(mpv);
    const std::string oldPause = ReadPropertyString(mpv, "pause");
    std::string oldSurfaceSize = ReadPropertyString(mpv, "ohos-surface-size");
    if (oldSurfaceSize.empty() && previousWidth >= 16 && previousHeight >= 16) {
        oldSurfaceSize = std::to_string(previousWidth) + "x" +
                          std::to_string(previousHeight);
    }
    const std::string surfaceSize = std::to_string(width) + "x" + std::to_string(height);

    // Preserve fallback modes such as "no" and "copy" verbatim; replacing
    // them with ohcodec can corrupt 10-bit output during the next frame.
    const OperationResult result = ApplySurfaceState(
        mpv, surfaceSize, surfaceId, oldVo, oldPause, oldSurfaceSize,
        surfaceId, oldHwdec);
    if (result.error < 0) {
        // Do not let the cache claim that the mpv transaction succeeded. The
        // native geometry is best-effort rolled back so a retry sees a
        // consistent surface as well.
        if (previousWidth >= 16 && previousHeight >= 16) {
            const int32_t rollbackCode = OH_NativeWindow_NativeWindowHandleOpt(
                window, SET_BUFFER_GEOMETRY, previousWidth, previousHeight);
            if (rollbackCode != 0) {
                OH_LOG_Print(static_cast<LogType>(LOG_APP), LOG_WARN,
                             LOG_DOMAIN, LOG_TAG,
                             "reconfigureSurface geometry rollback failed code=%{public}d",
                             rollbackCode);
            }
        }
        return result;
    }

    g_geoW.store(width);
    g_geoH.store(height);

    OH_LOG_Print(static_cast<LogType>(LOG_APP), LOG_INFO, LOG_DOMAIN, LOG_TAG,
                 "reconfigureSurface size=%{public}dx%{public}d geometry=%{public}d",
                 width, height, geometryCode);
    return Success();
}

OperationResult SwitchSurfaceOnMpv(mpv_handle *mpv, const MpvCommand &command) {
    const uint64_t sid = strtoull(command.surfaceId.c_str(), nullptr, 10);
    if (sid == 0) {
        return Failure(kInvalidArgument, "surface id must be a positive integer");
    }
    OHNativeWindow *nextWindow = nullptr;
    const int32_t createCode =
        OH_NativeWindow_CreateNativeWindowFromSurfaceId(sid, &nextWindow);
    if (createCode != 0 || nextWindow == nullptr) {
        return Failure(kNativeWindowFailure,
                       "CreateNativeWindowFromSurfaceId failed: " +
                           std::to_string(createCode));
    }

    const int32_t width = command.width >= 16 ? command.width
                                              : (g_geoW.load() >= 16 ? g_geoW.load() : 1920);
    const int32_t height = command.height >= 16 ? command.height
                                                 : (g_geoH.load() >= 16 ? g_geoH.load() : 1080);
    const int32_t geometryCode = OH_NativeWindow_NativeWindowHandleOpt(
        nextWindow, SET_BUFFER_GEOMETRY, width, height);
    if (geometryCode != 0) {
        OH_NativeWindow_DestroyNativeWindow(nextWindow);
        return Failure(kNativeWindowFailure,
                       "SET_BUFFER_GEOMETRY failed: " + std::to_string(geometryCode));
    }

    std::string oldSurfaceId;
    {
        std::lock_guard<std::mutex> lock(g_surfaceIdMutex);
        oldSurfaceId = g_surfaceId;
    }
    if (oldSurfaceId.empty()) {
        oldSurfaceId = ReadPropertyString(mpv, "wid");
    }
    const std::string oldVo = ReadPropertyString(mpv, "vo");
    const std::string oldHwdec = ReadActiveHwdec(mpv);
    const std::string oldPause = ReadPropertyString(mpv, "pause");
    std::string oldSurfaceSize = ReadPropertyString(mpv, "ohos-surface-size");
    const int32_t previousWidth = g_geoW.load();
    const int32_t previousHeight = g_geoH.load();
    if (oldSurfaceSize.empty() && previousWidth >= 16 && previousHeight >= 16) {
        oldSurfaceSize = std::to_string(previousWidth) + "x" +
                          std::to_string(previousHeight);
    }

    const OperationResult result = ApplySurfaceState(
        mpv, std::to_string(width) + "x" + std::to_string(height),
        command.surfaceId, oldVo, oldPause, oldSurfaceSize, oldSurfaceId,
        oldHwdec);
    if (result.error < 0) {
        OH_NativeWindow_DestroyNativeWindow(nextWindow);
        return result;
    }

    {
        std::lock_guard<std::mutex> lock(g_surfaceIdMutex);
        g_surfaceId = command.surfaceId;
    }
    OHNativeWindow *previousWindow = g_nativeWindow.exchange(nextWindow);
    if (previousWindow != nullptr) {
        OH_NativeWindow_DestroyNativeWindow(previousWindow);
    }
    g_geoW.store(width);
    g_geoH.store(height);
    OH_LOG_Print(static_cast<LogType>(LOG_APP), LOG_INFO,
                 LOG_DOMAIN, LOG_TAG,
                 "switchSurface applied gen=%{public}d size=%{public}dx%{public}d",
                 command.generation, width, height);
    return Success();
}

void ExecuteCommand(const MpvCommand &command) {
    mpv_handle *mpv = g_mpv.load();
    if (mpv == nullptr) {
        CompleteCommand(command, Failure(kBridgeClosed, "mpv bridge is not initialized"));
        return;
    }
    // Geometry reconfigs and surface switches operate on the plugin-wide
    // shared buffer / output surface, not on a per-room stream, so a
    // generation that is "stale" relative to a fast room switch must still be
    // allowed to run — otherwise the new room's correct-aspect reconfigure
    // gets dropped (the landscape->portrait squash), or the PiP surface switch
    // gets skipped and the small window stays blank while audio keeps playing.
    if (IsStaleGeneration(command) &&
        command.type != CommandType::RECONFIGURE_SURFACE &&
        command.type != CommandType::SET_GEOMETRY &&
        command.type != CommandType::SWITCH_SURFACE) {
        CompleteCommand(command, StaleResult(command));
        return;
    }
    switch (command.type) {
        case CommandType::LOAD_FILE: {
            if (command.generation <= 0) {
                CompleteCommand(command, Failure(kInvalidArgument,
                                                 "loadFile requires a positive generation"));
                return;
            }
            {
                std::lock_guard<std::mutex> lock(g_generationMutex);
                g_pendingGenerations.push_back(command.generation);
            }
            // Apply request-scoped headers immediately before loadfile so the
            // command queue preserves the same order as Dart's calls. An
            // empty value also clears headers from the previous stream.
            OperationResult result = SetPropertyOnMpv(mpv, "http-header-fields", command.headers);
            if (result.error >= 0 && IsStaleGeneration(command)) {
                RemovePendingGeneration(command.generation);
                result = StaleResult(command);
            }
            if (result.error >= 0) {
                result = LoadFileOnMpv(mpv, command.url);
            }
            if (result.error < 0) {
                RemovePendingGeneration(command.generation);
            }
            OH_LOG_Print(static_cast<LogType>(LOG_APP),
                         result.error < 0 ? LOG_ERROR : LOG_INFO,
                         LOG_DOMAIN,
                         LOG_TAG,
                         "loadFile stage=command gen=%{public}d status=%{public}d urlLength=%{public}zu headers=%{public}s",
                         command.generation,
                         result.error,
                         command.url.size(),
                         command.headers.empty() ? "empty" : "present");
            CompleteCommand(command, result);
            return;
        }
        case CommandType::SET_PROPERTY:
            CompleteCommand(command, SetPropertyOnMpv(mpv, command.name, command.value));
            return;
        case CommandType::COMMAND: {
            OperationResult result = CommandOnMpv(mpv, command.command);
            if (result.error >= 0 && command.command == "stop") {
                ClearPendingGenerations();
                g_fileLoaded.store(false);
            }
            CompleteCommand(command, result);
            return;
        }
        case CommandType::SET_GEOMETRY:
        case CommandType::RECONFIGURE_SURFACE: {
            CompleteCommand(command, ReconfigureSurfaceOnMpv(mpv, command.width, command.height));
            return;
        }
        case CommandType::SWITCH_SURFACE: {
            CompleteCommand(command, SwitchSurfaceOnMpv(mpv, command));
            return;
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
            if (g_commandStopping) {
                while (!g_commandQueue.empty()) {
                    CompleteCommand(g_commandQueue.front(),
                                    Failure(kBridgeClosed, "mpv bridge is shutting down"));
                    g_commandQueue.pop_front();
                }
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

struct AsyncCommandRequest {
    MpvCommand command;
    std::shared_ptr<Completion> completion = std::make_shared<Completion>();
    int32_t error = 0;
    std::string detail;
    napi_deferred deferred = nullptr;
    napi_async_work work = nullptr;
};

void RejectDeferred(napi_env env, napi_deferred deferred, int32_t error,
                    const char *detail) {
    napi_value message = nullptr;
    napi_create_string_utf8(env,
                            detail != nullptr ? detail
                                              : "native mpv bridge operation failed",
                            NAPI_AUTO_LENGTH, &message);
    napi_value reason = nullptr;
    napi_create_error(env, nullptr, message, &reason);
    napi_value code = nullptr;
    napi_create_int32(env, error, &code);
    napi_set_named_property(env, reason, "code", code);
    napi_reject_deferred(env, deferred, reason);
}

napi_value CreateRejectedPromise(napi_env env, int32_t error, const char *detail) {
    napi_deferred deferred = nullptr;
    napi_value promise = nullptr;
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "mpvCommand", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_promise(env, &deferred, &promise) != napi_ok) {
        return nullptr;
    }
    RejectDeferred(env, deferred, error, detail);
    return promise;
}

void ExecuteAsyncCommand(napi_env env, void *data) {
    auto *request = static_cast<AsyncCommandRequest *>(data);
    if (request == nullptr) {
        return;
    }
    request->error = request->completion->Wait(&request->detail);
}

void CompleteAsyncCommand(napi_env env, napi_status status, void *data) {
    auto *request = static_cast<AsyncCommandRequest *>(data);
    if (request == nullptr) {
        return;
    }
    if (status != napi_ok && request->error >= 0) {
        request->error = kBridgeClosed;
        request->detail = "mpv async work was cancelled";
    }
    if (request->error < 0) {
        RejectDeferred(env, request->deferred, request->error,
                       request->detail.empty()
                           ? "native mpv bridge operation failed"
                           : request->detail.c_str());
    } else {
        napi_value undefined = nullptr;
        napi_get_undefined(env, &undefined);
        napi_resolve_deferred(env, request->deferred, undefined);
    }
    napi_delete_async_work(env, request->work);
    delete request;
}

napi_value CreateCommandPromise(napi_env env, MpvCommand command) {
    napi_deferred deferred = nullptr;
    napi_value promise = nullptr;
    if (napi_create_promise(env, &deferred, &promise) != napi_ok) {
        return nullptr;
    }
    auto *request = new AsyncCommandRequest();
    request->command = std::move(command);
    request->command.completion = request->completion;
    request->deferred = deferred;

    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "mpvCommand", NAPI_AUTO_LENGTH, &resourceName);
    const napi_status workStatus = napi_create_async_work(
        env, nullptr, resourceName, ExecuteAsyncCommand, CompleteAsyncCommand,
        request, &request->work);
    if (workStatus != napi_ok) {
        delete request;
        RejectDeferred(env, deferred, kBridgeClosed,
                       "failed to create native mpv async work");
        return promise;
    }

    // Enqueue while still on the NAPI/UI call stack. Several Dart calls can
    // create async work in order, but NAPI's worker pool is free to start that
    // work in a different order. The native FIFO is the ordering boundary;
    // the worker below only waits for its already-enqueued completion.
    if (!QueueCommand(std::move(request->command))) {
        napi_delete_async_work(env, request->work);
        delete request;
        RejectDeferred(env, deferred, kBridgeClosed,
                       "mpv bridge is not accepting commands");
        return promise;
    }

    const napi_status queueStatus = napi_queue_async_work(env, request->work);
    if (queueStatus != napi_ok) {
        // The command is already in the native FIFO to preserve call order.
        // Reject this promise immediately; its shared completion is still
        // owned by the queued command and will be released after execution.
        napi_delete_async_work(env, request->work);
        delete request;
        RejectDeferred(env, deferred, kBridgeClosed,
                       "failed to queue native mpv async work");
    }
    return promise;
}

bool ReadStringArgument(napi_env env, napi_value value, std::string *result,
                        size_t maxLength = 65536) {
    if (value == nullptr || result == nullptr) {
        return false;
    }
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok ||
        length > maxLength) {
        return false;
    }
    std::string buffer(length + 1, '\0');
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, &buffer[0], buffer.size(), &copied) != napi_ok) {
        return false;
    }
    buffer.resize(copied);
    *result = std::move(buffer);
    return true;
}

bool ReadDimension(napi_env env, napi_value value, int32_t *result) {
    if (value == nullptr || result == nullptr) {
        return false;
    }
    double number = 0;
    if (napi_get_value_double(env, value, &number) != napi_ok ||
        !std::isfinite(number) || number < 16 || number > 32768) {
        return false;
    }
    *result = static_cast<int32_t>(number);
    return true;
}

bool ReadGeneration(napi_env env, napi_value value, int32_t *result,
                    bool required = true) {
    if (value == nullptr) {
        return !required;
    }
    double number = 0;
    if (napi_get_value_double(env, value, &number) != napi_ok ||
        !std::isfinite(number) || number < 1 || number > INT32_MAX ||
        std::floor(number) != number) {
        return false;
    }
    *result = static_cast<int32_t>(number);
    return true;
}

// Applies the requested buffer geometry. Called from Dart as part of the
// async vo reconfig sequence (vo=null -> setGeometry -> ohos-surface-size
// -> vo=gpu-next). Dart is the only writer: it drives this from the player
// widget's pixel size, never from the video dimensions.
napi_value SetGeometry(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t width = 0;
    int32_t height = 0;
    int32_t generation = 0;
    if (argc < 2 || !ReadDimension(env, args[0], &width) ||
        !ReadDimension(env, args[1], &height) ||
        (argc >= 3 && !ReadGeneration(env, args[2], &generation, false))) {
        return CreateRejectedPromise(env, kInvalidArgument,
                                     "setGeometry expects width, height, and an optional generation");
    }
    MpvCommand command;
    command.type = CommandType::RECONFIGURE_SURFACE;
    command.width = width;
    command.height = height;
    command.generation = generation;
    return CreateCommandPromise(env, std::move(command));
}

napi_value ReconfigureSurface(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t width = 0;
    int32_t height = 0;
    int32_t generation = 0;
    if (argc < 3 || !ReadDimension(env, args[0], &width) ||
        !ReadDimension(env, args[1], &height) ||
        !ReadGeneration(env, args[2], &generation)) {
        return CreateRejectedPromise(env, kInvalidArgument,
                                     "reconfigureSurface expects width, height, and generation");
    }
    MpvCommand command;
    command.type = CommandType::RECONFIGURE_SURFACE;
    command.width = width;
    command.height = height;
    command.generation = generation;
    return CreateCommandPromise(env, std::move(command));
}

napi_value SwitchSurface(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string surfaceId;
    int32_t generation = 0;
    int32_t width = 0;
    int32_t height = 0;
    if (argc < 2 || !ReadStringArgument(env, args[0], &surfaceId, 4096) ||
        surfaceId.empty() || !ReadGeneration(env, args[1], &generation) ||
        (argc >= 4 && (!ReadDimension(env, args[2], &width) ||
                       !ReadDimension(env, args[3], &height)))) {
        return CreateRejectedPromise(env, kInvalidArgument,
                                     "switchSurface expects surface id, generation, and optional size");
    }
    MpvCommand command;
    command.type = CommandType::SWITCH_SURFACE;
    command.surfaceId = std::move(surfaceId);
    command.generation = generation;
    command.width = width;
    command.height = height;
    return CreateCommandPromise(env, std::move(command));
}

std::atomic<int64_t> g_lastTimePosPushMs{0};
std::atomic<int64_t> g_lastCachePushMs{0};

// Synthesizes the Dart-visible "first frame" event once per generation.
// MPV_EVENT_VIDEO_RECONFIG fires when the vo is first configured (non-
// deprecated, faster than the tick); MPV_EVENT_TICK is the per-second
// fallback. Both share the same gates: an active generation, the
// video-out-params marker for that generation, a loaded file, a live core,
// and a one-shot CAS. A video reconfiguration by itself is not proof that a
// frame reached the output surface.
int32_t ParsePositiveDimension(const std::string &value) {
    if (value.empty()) {
        return 0;
    }
    char *end = nullptr;
    const long parsed = std::strtol(value.c_str(), &end, 10);
    if (end == value.c_str() || *end != '\0' || parsed < 16 || parsed > 32768) {
        return 0;
    }
    return static_cast<int32_t>(parsed);
}

void TryPresentFirstFrame() {
    const int32_t generation = g_activeGeneration.load();
    // First-frame gate, aligned with the reference player (聚映): the stream
    // is considered "rendering" once the file is loaded, the video core has
    // left idle (core-idle=no — mpv's authoritative "video is running" signal,
    // exactly what the reference player keys off for notifyVideoRendering) and
    // the rotation-aware display size (video-out-params/dw,dh) is known.
    //
    // The previous gate required g_videoParamsSeen (never set to true anywhere)
    // AND g_videoGeometryGeneration == generation (only ever written inside a
    // "video-out-params" map event whose STRING-observed value is always
    // empty). That made both conditions permanently false, so this function
    // returned early forever, the native "video-frame-presented" event never
    // fired, and Dart fell back to a slow, timing-fragile core-idle path —
    // the direct cause of the "刚进直播间特别卡 + 尺寸偶发错误" symptom.
    if (generation <= 0 ||
        !g_activePlayback.load() ||
        !g_fileLoaded.load() ||
        g_coreIdle.load() ||
        g_videoWidth.load() < 16 ||
        g_videoHeight.load() < 16) {
        return;
    }
    int32_t expected = g_framePresentedGeneration.load();
    if (expected == generation ||
        !g_framePresentedGeneration.compare_exchange_strong(expected, generation)) {
        return;
    }
    auto *payload = new EventPayload();
    payload->kind = "event";
    payload->name = "video-frame-presented";
    if (!QueueEvent(payload, generation)) {
        int32_t marked = generation;
        g_framePresentedGeneration.compare_exchange_strong(marked, -1);
    }
}

std::string LowerAscii(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
        return static_cast<char>(std::tolower(ch));
    });
    return value;
}

// Only decoder/VO diagnostics that the ArkTS policy can act on cross the
// native boundary. Generic mpv logs may contain URLs, cookies, or request
// headers, so they are intentionally dropped instead of being redacted with
// an incomplete parser.
bool BuildDecoderLogEvent(const mpv_event_log_message *message, EventPayload *payload) {
    if (message == nullptr || payload == nullptr || message->text == nullptr) {
        return false;
    }
    const std::string lower = LowerAscii(message->text);
    std::string category;
    std::string safeText;
    if (lower.find("surface interop failed") != std::string::npos ||
        lower.find("timed out waiting for rendered ohcodec surface buffer") !=
            std::string::npos) {
        category = "interop-failure";
        safeText = lower.find("timed out") != std::string::npos
            ? "Timed out waiting for rendered OHCodec Surface buffer"
            : "OHCodec Surface interop failed";
    } else if (lower.find("missing parameter sets") != std::string::npos ||
               lower.find("parameter sets") != std::string::npos ||
               lower.find("sps") != std::string::npos ||
               lower.find("pps") != std::string::npos ||
               lower.find("bootstrapped") != std::string::npos) {
        category = "decoder-bootstrap";
        safeText = "decoder parameter-set bootstrap diagnostic";
    } else if (lower.find("p010") != std::string::npos ||
               lower.find("10bit") != std::string::npos ||
               lower.find("high_depth=1") != std::string::npos) {
        category = "decoder-10bit";
        safeText = "10-bit decoder format detected";
    } else if (lower.find("bt.2020") != std::string::npos ||
               lower.find("bt2020") != std::string::npos ||
               lower.find("pq") != std::string::npos ||
               lower.find("colorspace") != std::string::npos) {
        category = "hdr-output";
        safeText = "HDR colorspace output diagnostic";
    } else if (lower.find("falling back") != std::string::npos ||
               lower.find("hardware decoding") != std::string::npos ||
               lower.find("could not create") != std::string::npos ||
               lower.find("ohcodec") != std::string::npos) {
        category = "hwdec";
        safeText = "hardware decoder diagnostic";
    } else {
        return false;
    }
    payload->kind = "decoder";
    payload->name = category;
    payload->category = category;
    payload->level = message->level != nullptr ? message->level : "";
    payload->value = payload->level;
    payload->text = std::move(safeText);
    return true;
}

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
            case MPV_EVENT_SET_PROPERTY_REPLY:
            case MPV_EVENT_COMMAND_REPLY:
                CompleteMpvReply(ev->reply_userdata, ev->error,
                                 ev->error < 0 ? MpvErrorText(ev->error) : "");
                break;
            case MPV_EVENT_PROPERTY_CHANGE: {
                auto *prop = static_cast<mpv_event_property *>(ev->data);
                auto *payload = new EventPayload();
                payload->kind = "property";
                payload->name = prop != nullptr && prop->name != nullptr ? prop->name : "";
                if (prop == nullptr) {
                    delete payload;
                    break;
                }
                if (prop->format == MPV_FORMAT_STRING && prop->data != nullptr) {
                    // mpv may report an observed string property before it has
                    // a value. In that case data points to a null char*;
                    // constructing std::string from it would crash the app
                    // during player startup.
                    const char *stringValue =
                        *static_cast<const char **>(prop->data);
                    payload->value = stringValue != nullptr ? stringValue : "";
                } else if (prop->format == MPV_FORMAT_FLAG && prop->data != nullptr) {
                    payload->value = *static_cast<int *>(prop->data) != 0 ? "true" : "false";
                } else if (prop->format == MPV_FORMAT_INT64 && prop->data != nullptr) {
                    payload->value = std::to_string(*static_cast<int64_t *>(prop->data));
                } else if (prop->format == MPV_FORMAT_DOUBLE && prop->data != nullptr) {
                    payload->value = std::to_string(*static_cast<double *>(prop->data));
                } else {
                    payload->value = "";
                }
                const std::string propertyName = prop->name != nullptr ? prop->name : "";
                if (propertyName == "video-out-params/dw" || propertyName == "width") {
                    const int32_t width = ParsePositiveDimension(payload->value);
                    if (width > 0) {
                        g_videoWidth.store(width);
                    }
                } else if (propertyName == "video-out-params/dh" || propertyName == "height") {
                    const int32_t height = ParsePositiveDimension(payload->value);
                    if (height > 0) {
                        g_videoHeight.store(height);
                    }
                } else if (propertyName == "core-idle") {
                    g_coreIdle.store(payload->value != "no" && payload->value != "false");
                }
                if (propertyName == "time-pos" ||
                    propertyName == "demuxer-cache-duration") {
                    int64_t now = std::chrono::duration_cast<std::chrono::milliseconds>(
                        std::chrono::steady_clock::now().time_since_epoch()).count();
                    int64_t last = propertyName == "time-pos"
                        ? g_lastTimePosPushMs.load()
                        : g_lastCachePushMs.load();
                    if (now - last < 250) {
                        delete payload;
                        break;
                    }
                    if (propertyName == "time-pos") {
                        g_lastTimePosPushMs.store(now);
                    } else {
                        g_lastCachePushMs.store(now);
                    }
                }
                QueueEvent(payload);
                if (propertyName == "video-out-params/dw" ||
                    propertyName == "video-out-params/dh" ||
                    propertyName == "core-idle") {
                    TryPresentFirstFrame();
                }
                break;
            }
            case MPV_EVENT_LOG_MESSAGE: {
                auto *msg = static_cast<mpv_event_log_message *>(ev->data);
                auto *payload = new EventPayload();
                // Generic mpv logs may include stream URLs and request
                // headers. Forward only the small diagnostic allowlist that
                // the decoder policy can act on, in normalized form.
                if (!BuildDecoderLogEvent(msg, payload)) {
                    delete payload;
                    break;
                }
                QueueEvent(payload);
                break;
            }
            case MPV_EVENT_END_FILE: {
                auto *eef = static_cast<mpv_event_end_file *>(ev->data);
                const int32_t generation = g_activeGeneration.load();
                const char *reason = "unknown";
                switch (eef != nullptr ? eef->reason : MPV_END_FILE_REASON_ERROR) {
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
                payload->gen = generation;
                if (eef != nullptr) {
                    payload->code = eef->error;
                    if (eef->error < 0) {
                        payload->text = MpvErrorText(eef->error);
                    }
                }
                QueueEvent(payload, generation);
                break;
            }
            case MPV_EVENT_START_FILE: {
                const int32_t generation = ActivateNextGeneration();
                g_videoWidth.store(0);
                g_videoHeight.store(0);
                g_fileLoaded.store(false);
                g_coreIdle.store(true);
                g_activePlayback.store(generation > 0);
                auto *payload = new EventPayload();
                payload->kind = "event";
                payload->name = "start-file";
                QueueEvent(payload, generation);
                break;
            }
            case MPV_EVENT_VIDEO_RECONFIG:
#if MPV_ENABLE_DEPRECATED
            case MPV_EVENT_TICK:
#endif
                TryPresentFirstFrame();
                break;
            case MPV_EVENT_IDLE:
            case MPV_EVENT_FILE_LOADED: {
                if (ev->event_id == MPV_EVENT_IDLE) {
                    g_coreIdle.store(true);
                } else {
                    g_fileLoaded.store(true);
                }
                auto *payload = new EventPayload();
                payload->kind = "event";
                payload->name = mpv_event_name(ev->event_id);
                QueueEvent(payload);
                if (ev->event_id == MPV_EVENT_FILE_LOADED) {
                    TryPresentFirstFrame();
                }
                break;
            }
            case MPV_EVENT_SHUTDOWN: {
                auto *payload = new EventPayload();
                payload->kind = "event";
                payload->name = "shutdown";
                QueueEvent(payload);
                FailMpvReplies(kBridgeClosed, "mpv reported shutdown");
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
    napi_value codeVal = nullptr;
    napi_create_int32(env, payload->code, &codeVal);
    napi_set_named_property(env, event, "kind", kind);
    napi_set_named_property(env, event, "name", name);
    napi_set_named_property(env, event, "value", value);
    napi_set_named_property(env, event, "text", text);
    napi_set_named_property(env, event, "gen", genVal);
    napi_set_named_property(env, event, "code", codeVal);
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
    {
        std::lock_guard<std::mutex> lock(g_surfaceIdMutex);
        g_surfaceId = surfaceId;
    }
    mpv_set_option_string(mpv, "wid", surfaceId);
    mpv_set_option_string(mpv, "vo", "gpu-next");
    mpv_set_option_string(mpv, "gpu-context", "ohosvk");
    mpv_set_option_string(mpv, "gpu-api", "vulkan");
    mpv_set_option_string(mpv, "hwdec", "ohcodec");
    mpv_set_option_string(mpv, "hwdec-software-fallback", "3");
    // Live playback uses a no-cache / low-latency baseline aligned with the
    // reference player (聚映); Dart applies the rest of the live profile on
    // top of this shared video-sync baseline.
    mpv_set_option_string(mpv, "video-sync", "desync");
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
    mpv_request_log_messages(mpv, "warn");
#if MPV_ENABLE_DEPRECATED
    const int tickError = mpv_request_event(mpv, MPV_EVENT_TICK, 1);
    if (tickError < 0) {
        OH_LOG_Print(static_cast<LogType>(LOG_APP), LOG_WARN, LOG_DOMAIN, LOG_TAG,
                     "mpv tick event unavailable code=%{public}d", tickError);
    }
#endif
    mpv_request_event(mpv, MPV_EVENT_VIDEO_RECONFIG, 1);
    const char *observed[] = {
        "pause", "core-idle", "paused-for-cache", "eof-reached",
        "cache-buffering-state", "hwdec-current", "video-codec",
        "video-format", "estimated-vf-fps", "frame-drop-count",
        "decoder-frame-drop-count",
        // Observe the rotation-aware display dimensions individually. These two
        // leaf properties feed g_videoWidth/g_videoHeight (first-frame gate) and
        // are what Dart reads for the correct stream aspect. The parent
        // "video-out-params" map serializes to an empty STRING under
        // MPV_FORMAT_STRING and is deliberately NOT observed — it carries no
        // usable value and only produced a deadlock in the old first-frame gate.
        "video-out-params/dw", "video-out-params/dh",
        "time-pos", "demuxer-cache-duration", "width", "height", "paused",
    };
    for (const char *name : observed) {
        mpv_observe_property(mpv, 0, name, MPV_FORMAT_STRING);
    }

    ClearPendingGenerations();
    g_activeGeneration.store(0);
    g_latestRequestedGeneration.store(0);
    g_activePlayback.store(false);
    g_framePresentedGeneration.store(-1);
    {
        std::lock_guard<std::mutex> lock(g_commandMutex);
        g_commandQueue.clear();
        g_commandStopping = false;
        g_commandAccepting = true;
    }
    {
        std::lock_guard<std::mutex> lock(g_replyMutex);
        g_repliesClosed = false;
    }
    g_commandThread = std::thread(CommandLoop);
    g_running.store(true);
    g_eventThread = std::thread(EventLoop);
    // The reference integration writes post-initialize properties through the
    // command/event path. Queue the initial surface size after both workers
    // are alive so its async reply cannot block startup or the UI thread.
    char surfaceSizeOpt[64] = {0};
    snprintf(surfaceSizeOpt, sizeof(surfaceSizeOpt), "%.0fx%.0f", surfaceWidth, surfaceHeight);
    MpvCommand initialSurfaceSize;
    initialSurfaceSize.type = CommandType::SET_PROPERTY;
    initialSurfaceSize.name = "ohos-surface-size";
    initialSurfaceSize.value = surfaceSizeOpt;
    QueueCommand(std::move(initialSurfaceSize));
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
    g_latestRequestedGeneration.store(generation);
    QueueCommand(std::move(command));
    return nullptr;
}

napi_value SetPropertyString(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        return CreateRejectedPromise(env, kInvalidArgument,
                                     "setPropertyString expects name and value");
    }
    if (g_mpv.load() == nullptr) {
        return CreateRejectedPromise(env, kBridgeClosed,
                                     "mpv bridge is not initialized");
    }
    size_t len = 0;
    char name[256] = {0};
    napi_get_value_string_utf8(env, args[0], name, sizeof(name), &len);
    char value[4096] = {0};
    napi_get_value_string_utf8(env, args[1], value, sizeof(value), &len);
    int32_t generation = 0;
    if (argc >= 3 && !ReadGeneration(env, args[2], &generation, false)) {
        return CreateRejectedPromise(env, kInvalidArgument,
                                     "setPropertyString generation is invalid");
    }
    MpvCommand command;
    command.type = CommandType::SET_PROPERTY;
    command.name = name;
    command.value = value;
    command.generation = generation;
    return CreateCommandPromise(env, std::move(command));
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
    // Close reply registration and cancel existing waiters before joining
    // the command worker. Registration and closure share a mutex, so a
    // racing transaction cannot start another wait after the cancellation.
    {
        std::lock_guard<std::mutex> lock(g_commandMutex);
        g_commandAccepting = false;
        g_commandStopping = true;
    }
    g_commandCv.notify_all();
    FailMpvReplies(kBridgeClosed, "mpv bridge is shutting down");
    if (g_commandThread.joinable()) {
        g_commandThread.join();
    }
    g_running.store(false);
    mpv_wakeup(mpv);
    if (g_eventThread.joinable()) {
        g_eventThread.join();
    }
    mpv_terminate_destroy(mpv);
    g_mpv.store(nullptr);
    OHNativeWindow *window = g_nativeWindow.exchange(nullptr);
    if (window != nullptr) {
        OH_NativeWindow_DestroyNativeWindow(window);
    }
    ClearPendingGenerations();
    g_activeGeneration.store(0);
    g_latestRequestedGeneration.store(0);
    g_activePlayback.store(false);
    g_fileLoaded.store(false);
    g_coreIdle.store(true);
    g_videoWidth.store(0);
    g_videoHeight.store(0);
    g_framePresentedGeneration.store(-1);
    LogMpv(LOG_INFO, "mpv destroyed");
    return nullptr;
}

// Returns the native buffer geometry currently in effect (g_geoW/g_geoH).
// The buffer is a plugin-wide singleton shared across Dart controllers, so
// a freshly created controller must read this to learn the REAL surface
// size instead of assuming the 1920x1080 default — otherwise a portrait
// buffer left by the previous room makes the next landscape stream look
// squashed (the Dart side skips the reconfig, believing the buffer already
// matches).
napi_value GetSurfaceSize(napi_env env, napi_callback_info info) {
    napi_value result = nullptr;
    napi_create_object(env, &result);
    const int32_t w = g_geoW.load();
    const int32_t h = g_geoH.load();
    napi_value wv = nullptr;
    napi_value hv = nullptr;
    napi_create_int32(env, w, &wv);
    napi_create_int32(env, h, &hv);
    napi_set_named_property(env, result, "width", wv);
    napi_set_named_property(env, result, "height", hv);
    return result;
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
        {"reconfigureSurface", nullptr, ReconfigureSurface, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"switchSurface", nullptr, SwitchSurface, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getSurfaceSize", nullptr, GetSurfaceSize, nullptr, nullptr, nullptr, napi_default, nullptr},
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
