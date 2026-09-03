#!/bin/bash

set -eu

ROOT_DIR=$(cd $(dirname "$0")/..; pwd)

. $ROOT_DIR/download/deps-version.sh

pushd $ROOT_DIR/libmpv

# 下面每个依赖都是「目录存在就跳过下载」。这是刻意的：源码改动发生在构建副本里
# （BUILD-NOTES §10），重下会毁掉尚未导出成 patch 的工作。
# 但由此带来一个陷阱——改了 deps-version.sh 的版本号却没删目录时，构建的仍是旧版本，
# 且不产生任何提示。故给每个依赖记版本戳：对不上就停下报错，由人确认后手工删，
# 脚本绝不自作主张删除任何依赖目录。
STAMP_DIR=.dep-versions
mkdir -p $STAMP_DIR

# dovi_tools / lcms / lua 已不在此表内：三者都不再下载，见文件下方对应位置的说明。
# mpv 的戳记的是分支名而非 SHA，因为 SHA 那一维由下方 verify_mpv_sha 直接比对
# 工作树的真实 HEAD，比戳更强；戳只负责「分支换了没有」。
DEPS=(
  "mbedtls:$V_MBEDTLS"
  "dav1d:$V_DAV1D"
  "libxml2:$V_LIBXML2"
  "fribidi:$V_FRIBIDI"
  "freetype:$V_FREETYPE"
  "harfbuzz:$V_HARFBUZZ"
  "fontconfig:$V_FONTCONFIG"
  "shaderc:$V_SHADERC"
  "ffmpeg:$V_FFMPEG"
  "libass:$V_LIBASS"
  "libplacebo:$V_LIBPLACEBO"
  "mpv:$V_MPV"
)

for entry in "${DEPS[@]}"; do
  dep=${entry%%:*}
  want=${entry#*:}
  # 目录不存在则本轮会下载，戳在末尾统一写。
  [ -d "$dep" ] || continue
  # 本次改动之前建立的构建树没有戳，按现状认领，避免对既有工作副本误报。
  [ -f "$STAMP_DIR/$dep" ] || continue
  have=$(cat "$STAMP_DIR/$dep")
  if [ "$have" != "$want" ]; then
    echo "ERROR: libmpv/$dep 已存在，但版本与 download/deps-version.sh 不一致。" >&2
    echo "       目录里是 $have，期望 $want。" >&2
    echo "       脚本不会自动删除：该目录可能有尚未导出成 patch 的源码改动。" >&2
    echo "       确认无未保存改动后手工删除再重跑： rm -rf libmpv/$dep" >&2
    exit 1
  fi
done

# mbedtls
if [ ! -d mbedtls ]; then
  echo "Downloading mbedtls..."
	mkdir mbedtls
	wget -qO mbedtls.tar.bz2 https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$V_MBEDTLS/mbedtls-$V_MBEDTLS.tar.bz2
  tar -C mbedtls --strip-components=1 -jxf mbedtls.tar.bz2
  rm mbedtls.tar.bz2
else
  echo "mbedtls already exists, skipping."
fi

# dav1d
if [ ! -d dav1d ]; then
  echo "Downloading dav1d..."
  git -c advice.detachedHead=false clone -q --depth 1 -b $V_DAV1D https://code.videolan.org/videolan/dav1d.git dav1d > /dev/null
else
  echo "dav1d already exists, skipping."
fi

# libxml2
if [ ! -d libxml2 ]; then
  echo "Downloading libxml2..."
  git -c advice.detachedHead=false clone -q --depth 1 -b $V_LIBXML2 --recursive https://gitlab.gnome.org/GNOME/libxml2.git libxml2 > /dev/null
else
  echo "libxml2 already exists, skipping."
fi

# fribidi
if [ ! -d fribidi ]; then
  echo "Downloading fribidi..."
  git -c advice.detachedHead=false clone -q --depth 1 -b $V_FRIBIDI https://github.com/fribidi/fribidi.git fribidi > /dev/null
else
  echo "fribidi already exists, skipping."
fi

# freetype
if [ ! -d freetype ]; then
  echo "Downloading freetype..."
  git -c advice.detachedHead=false clone -q --depth 1 -b $V_FREETYPE https://gitlab.freedesktop.org/freetype/freetype.git freetype > /dev/null
else
  echo "freetype already exists, skipping."
fi

# harfbuzz
if [ ! -d harfbuzz ]; then
  echo "Downloading harfbuzz..."
  git -c advice.detachedHead=false clone -q --depth 1 -b $V_HARFBUZZ https://github.com/harfbuzz/harfbuzz.git harfbuzz > /dev/null
else
  echo "harfbuzz already exists, skipping."
fi

# fontconfig
if [ ! -d fontconfig ]; then
  echo "Downloading fontconfig..."
  git -c advice.detachedHead=false clone -q --depth 1 -b $V_FONTCONFIG https://gitlab.freedesktop.org/fontconfig/fontconfig.git fontconfig > /dev/null
else
  echo "fontconfig already exists, skipping."
fi

# dovi_tools / lcms —— 已停用，源码不再下载。
# libplacebo 关掉了 -Ddovi / -Dlibdovi / -Dlcms，build.sh 也不再构建这两个依赖，
# 继续克隆只是白花 CI 时间（dovi_tool 是个 Rust 仓）。
#
# 要改回启用，四处都要动，缺一处就会以「找不到目录」或「meson 找不到依赖」的形式失败：
#   1. scripts/libplacebo.sh  -Ddovi=enabled -Dlibdovi=enabled / -Dlcms=enabled
#   2. build.sh               加回 ./scripts/dovi_tools.sh build 与 ./scripts/lcms.sh build
#   3. download.sh            取消注释 ./download/download-ohos-rs.sh（libdovi 是 Rust 实现）
#   4. 本文件                 取消注释下面两块，并把 dovi_tools / lcms 加回 DEPS 数组
# （lcms 只需要 2 与 4；Rust 工具链只服务 dovi。）
#
# if [ ! -d dovi_tools ]; then
#   echo "Downloading dovi_tools..."
#   git -c advice.detachedHead=false clone -q --depth 1 -b $V_DOVI_TOOLS https://github.com/quietvoid/dovi_tool.git dovi_tools > /dev/null
# else
#   echo "dovi_tools already exists, skipping."
# fi
#
# if [ ! -d lcms ]; then
#   echo "Downloading lcms..."
#   git -c advice.detachedHead=false clone -q --depth 1 -b $V_LCMS https://github.com/mm2/Little-CMS.git lcms > /dev/null
# else
#   echo "lcms already exists, skipping."
# fi

# shaderc
if [ ! -d shaderc ]; then
  echo "Downloading shaderc..."
  git -c advice.detachedHead=false clone -q --depth 1 -b $V_SHADERC https://github.com/google/shaderc.git shaderc > /dev/null
  cd shaderc
  ./utils/git-sync-deps > /dev/null
  cd ..
else
  echo "shaderc already exists, skipping."
fi

# ffmpeg
if [ ! -d ffmpeg ]; then
  echo "Downloading ffmpeg..."
  git -c advice.detachedHead=false clone -q --depth 1 -b $V_FFMPEG https://code.ffmpeg.org/FFmpeg/FFmpeg.git ffmpeg > /dev/null
else
  echo "ffmpeg already exists, skipping."
fi

# libass
if [ ! -d libass ]; then
  echo "Downloading libass..."
  git -c advice.detachedHead=false clone -q --depth 1 -b $V_LIBASS https://github.com/libass/libass.git libass > /dev/null
else
  echo "libass already exists, skipping."
fi

# libplacebo
if [ ! -d libplacebo ]; then
  echo "Downloading libplacebo..."
  git -c advice.detachedHead=false clone -q --depth 1 -b $V_LIBPLACEBO --recursive https://code.videolan.org/videolan/libplacebo.git libplacebo > /dev/null
else
  echo "libplacebo already exists, skipping."
fi

# lua —— 已停用，源码不再下载。mpv 关掉了 -Dlua（消费方不使用 mpv 脚本），
# build.sh 也不再构建它。要改回启用：mpv.sh 的 -Dlua=enabled + build.sh 加回
# ./scripts/lua.sh build + 取消注释下面这块 + 把 lua 加回 DEPS 数组。
#
# if [ ! -d lua ]; then
#   echo "Downloading lua..."
#   mkdir lua
#   wget -qO lua.tar.gz https://www.lua.org/ftp/lua-$V_LUA.tar.gz
#   tar -C lua --strip-components=1 -zxf lua.tar.gz
#   rm lua.tar.gz
# else
#   echo "lua already exists, skipping."
# fi

# mpv
# V_MPV 指向的是分支（refs/heads/）而非 tag，上游一次 force-push 就能让构建静默改变，
# 且 --depth 1 之后无法回溯到旧提交，故额外钉一个期望 SHA。
#
# 校验对「新克隆」与「已存在的构建树」都要做。只查新克隆是不够的：mpv 的版本戳记的是
# 分支名，force-push 后戳依然一致，那样两道防线会在最常见的既有树场景下同时失效。
# 每次都查也不会误报——patch.sh 用 git apply 打在工作区、不产生 commit，
# BUILD-NOTES §10 的导出流程也是 git diff HEAD，所以既有树的 HEAD 恒等于钉定值。
verify_mpv_sha() {
  local got
  if ! got=$(git -C mpv rev-parse HEAD 2>/dev/null); then
    echo "ERROR: libmpv/mpv 不是一个 git 仓库，无法校验 V_MPV_SHA。" >&2
    echo "       确认它不是残留的半截目录后删除再重跑： rm -rf libmpv/mpv" >&2
    exit 1
  fi
  if [ "$got" = "$V_MPV_SHA" ]; then
    return 0
  fi
  echo "ERROR: libmpv/mpv 的 HEAD 与 download/deps-version.sh 钉定的 V_MPV_SHA 不一致。" >&2
  echo "       期望 $V_MPV_SHA" >&2
  echo "       实际 $got" >&2
  if [ "$1" = "fresh" ]; then
    echo "       刚 clone 到的分支 $V_MPV 已不是钉定的那个提交，上游有新提交或被 force-push。" >&2
    echo "       确认改动可接受后，把 V_MPV_SHA 更新为实际值再重跑。" >&2
  else
    echo "       这是已存在的构建树，其 HEAD 与当前钉定值不同。" >&2
    echo "       要切到钉定版本：先按 BUILD-NOTES §10 导出 libmpv/mpv 里未保存的源码改动，" >&2
    echo "       再 rm -rf libmpv/mpv 重跑；若本地树才是对的，则更正 V_MPV_SHA。" >&2
    echo "       若你在构建副本里做过本地 commit 也会走到这里——请改回「工作区改动 +" >&2
    echo "       git diff HEAD 导出」的方式，否则 HEAD 会持续漂移。" >&2
  fi
  exit 1
}

if [ ! -d mpv ]; then
  echo "Downloading mpv..."
  git -c advice.detachedHead=false clone -q --depth 1 -b $V_MPV https://github.com/ErBWs/mpv.git mpv > /dev/null
  verify_mpv_sha fresh
else
  echo "mpv already exists, skipping."
  verify_mpv_sha existing
fi

# 下载成功后统一写版本戳（含首次为既有构建树补戳）。
for entry in "${DEPS[@]}"; do
  dep=${entry%%:*}
  [ -d "$dep" ] && echo "${entry#*:}" > $STAMP_DIR/$dep
done

popd
