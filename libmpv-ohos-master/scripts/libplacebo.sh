#!/bin/bash

set -eu

ROOT_DIR=$(cd $(dirname "$0")/..; pwd)

. $ROOT_DIR/env.sh

pushd $ROOT_DIR/libmpv/libplacebo

if [ "${1:-}" == "build" ]; then
	echo -e "\nBuilding libplacebo..."
elif [ "${1:-}" == "clean" ]; then
	rm -rf .build
	exit 0
else
	echo "Usage: $0 {build|clean}" >&2
	exit 1
fi

mkdir -p .build
cd .build

# 关掉的三项都已核实为死重量，勿轻易改回：
#   opengl  消费方在 mpv_napi.cpp:208 硬设 gpu-api=vulkan，GL 在 XComponent(SURFACE)
#           上必然 EGL_BAD_MATCH，整个 GL 后端一行都跑不到。
#   lcms    仅服务 ICC profile 变换（pl_icc_*）；HDR tone-map 走 libplacebo 自身实现。
#           已确认消费方未设 icc-profile 选项。mpv 侧另有独立的 lcms2 选项，需一并关。
#   dovi    Dolby Vision RPU 解析（libdovi 为 Rust 实现）。直播源没有 DV。
#           关掉后 dovi_tools 与整条 OHOS Rust 工具链都可从构建流程中摘除。
#
# 已配置时走 --reconfigure，避免 Directory already configured。
# 改 built-in option（如 c_link_args）仍须 clean，见 BUILD-NOTES §5 陷阱 2。
setup_cmd=(meson setup)
[ -f build.ninja ] && setup_cmd+=(--reconfigure)
"${setup_cmd[@]}" .. \
  --cross-file $ROOT_DIR/libmpv/arm64-crossfile.ini \
  --prefix=$DEST \
  -Ddovi=disabled \
  -Dlibdovi=disabled \
  -Dlcms=disabled \
  -Dshaderc=enabled \
  -Dvulkan=enabled \
  -Dopengl=disabled \
  -Ddemos=false
ninja -j$CORES
ninja install

popd