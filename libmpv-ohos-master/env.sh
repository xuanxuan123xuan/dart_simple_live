#!/bin/bash

set -eu

ROOT_DIR=$(cd $(dirname "$0")/..; pwd)

if [ "$(uname -s)" = "Linux" ]; then
  export OHOS_NDK_HOME=/sdk/linux
  export CORES=$(nproc)
elif [ "$(uname -s)" = "Darwin" ]; then
  export OHOS_NDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony
  export CORES=$(sysctl -n hw.ncpu)
fi

export DEST=$ROOT_DIR/libmpv/arm64-build
export PATH=$OHOS_NDK_HOME/native/build-tools/cmake/bin:$PATH
export PKG_CONFIG_PATH=$DEST/lib/pkgconfig
export PKG_CONFIG_LIBDIR=$OHOS_NDK_HOME/native/sysroot/usr/lib
export PKG_CONFIG_INCLUDEDIR=$OHOS_NDK_HOME/native/sysroot/usr/include

export AS=$OHOS_NDK_HOME/native/llvm/bin/llvm-as
export CC="$OHOS_NDK_HOME/native/llvm/bin/clang --target=aarch64-linux-ohos --sysroot=$OHOS_NDK_HOME/native/sysroot"
export CXX="$OHOS_NDK_HOME/native/llvm/bin/clang++ --target=aarch64-linux-ohos --sysroot=$OHOS_NDK_HOME/native/sysroot"
export LD=$OHOS_NDK_HOME/native/llvm/bin/ld.lld
export STRIP=$OHOS_NDK_HOME/native/llvm/bin/llvm-strip
export RANLIB=$OHOS_NDK_HOME/native/llvm/bin/llvm-ranlib
export OBJDUMP=$OHOS_NDK_HOME/native/llvm/bin/llvm-objdump
export OBJCOPY=$OHOS_NDK_HOME/native/llvm/bin/llvm-objcopy
export NM=$OHOS_NDK_HOME/native/llvm/bin/llvm-nm
export AR=$OHOS_NDK_HOME/native/llvm/bin/llvm-ar
# -ffunction-sections / -fdata-sections 让 mpv 链接期的 --gc-sections 能按函数回收；
# 不加时对纯 C 代码只能按整个 .o 回收，而静态库本就按需拉 .o，收益近乎为零。
# 这里覆盖的是读环境变量的构建系统：FFmpeg（configure，已实测 CFLAGS 会进 config.mak）
# 与 mbedtls（Makefile 用 CFLAGS ?=）。meson 依赖走 crossfiles/*.ini 的 c_args；
# shaderc 走 CMake，OHOS 工具链文件已默认带这两个 flag。
export CFLAGS='-fPIC -D__MUSL__=1 -ffunction-sections -fdata-sections'
export CXXFLAGS='-fPIC -D__MUSL__=1 -ffunction-sections -fdata-sections'
