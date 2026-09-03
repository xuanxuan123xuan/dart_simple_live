#!/bin/bash

set -eu

# ffmpeg
./scripts/mbedtls.sh build
./scripts/dav1d.sh build
./scripts/ffmpeg.sh build

# fontconfig
./scripts/libxml2.sh build

# libass
./scripts/fribidi.sh build
./scripts/freetype.sh build
./scripts/harfbuzz.sh build
./scripts/fontconfig.sh build
./scripts/libass.sh build

# libplacebo
# dovi_tools（libdovi）与 lcms 已从 libplacebo 配置中关闭，故不再构建，
# 且源码也不再下载（见 download/download-deps.sh 对应位置，那里列了完整的恢复步骤）。
# scripts/dovi_tools.sh 与 scripts/lcms.sh 保留待用。
./scripts/shaderc.sh build
./scripts/libplacebo.sh build

# mpv
# lua 已从 mpv 配置中关闭（消费方不用 mpv 脚本），故不再构建，源码同样不再下载。
./scripts/mpv.sh build
