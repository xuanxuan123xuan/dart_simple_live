#!/bin/bash

set -eu

# OpenHarmony SDK version
V_SDK=6.0-Release

# FFmpeg
V_MBEDTLS=3.6.4
V_DAV1D=1.5.1

# fontconfig
V_LIBXML2=v2.15.1

# libass
V_FRIBIDI=v1.0.16
V_FREETYPE=VER-2-13-3
V_HARFBUZZ=11.4.5
V_FONTCONFIG=2.17.1

# libplacebo
# V_DOVI_TOOLS / V_LCMS 当前未被使用：dovi 与 lcms 已从 libplacebo 关闭，
# 源码不再下载也不再构建。版本号保留在此，改回启用时不必重新考证。
V_DOVI_TOOLS=2.3.1
V_LCMS=lcms2.17
V_SHADERC=v2025.4

# mpv
V_FFMPEG=n8.0
V_LIBASS=0.17.4
V_LIBPLACEBO=v7.360.1
# V_LUA 同上：mpv 已关掉 -Dlua，源码不再下载也不再构建。
V_LUA=5.2.4
V_MPV=feat-ohos-0.41.0
# V_MPV 是 fork 上的分支不是 tag，单靠分支名无法锁定源码。
# 更新分支时同步改这里；查当前值：
#   git ls-remote --heads https://github.com/ErBWs/mpv.git feat-ohos-0.41.0
V_MPV_SHA=6edeee00a07b9b76f197aa71eee3d029fb090de4
