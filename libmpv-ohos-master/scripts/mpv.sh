#!/bin/bash

set -eu

ROOT_DIR=$(cd $(dirname "$0")/..; pwd)

. $ROOT_DIR/env.sh

pushd $ROOT_DIR/libmpv/mpv

if [ "${1:-}" == "build" ]; then
	echo -e "\nBuilding mpv..."
elif [ "${1:-}" == "clean" ]; then
	rm -rf .build
	exit 0
else
	echo "Usage: $0 {build|clean}" >&2
	exit 1
fi

mkdir -p .build
cd .build

# 体积优化链接参数（实测 23.66 MiB → 19.28 MiB，符号差分零回归；详见 BUILD-NOTES.md）：
#   --version-script        只导出 mpv_* 这 54 个 API。mpv 为支持 cplugins 自带 -rdynamic，
#                           会把 16887 个符号全量导出；这不只浪费 1.4 MiB 符号表，更关键的是
#                           让链接器不敢回收任何符号，--gc-sections 因此完全失效。
#   --gc-sections           回收未被引用的 section，必须与 version-script 同时启用才有收益
#                           （单独加只省 0.05 MiB，叠加后省 3.74 MiB）。
#   --pack-dyn-relocs=relr  .rela.dyn 1132K → RELA 31K + RELR 14K。OHOS musl 的
#                           libc.so / libz.so 自身即带 DT_RELR，运行时支持已确认。
# 未启用 --icf：其失败模式是「不同函数被合并到同一地址」，符号差分查不出来，
#   而收益仅 0.33 MiB（HAP 压缩后约 80 KB），风险收益比不划算。
#
# c_link_args 会整体覆盖 crossfile 的 [built-in options] 同名值，故必须把 crossfile
# 里原有的三项一并重复。修改 crossfiles/*.ini 的 c_link_args 时此处需同步。
MPV_LINK_ARGS="--target=aarch64-linux-ohos -fuse-ld=lld -lc++_shared"
MPV_LINK_ARGS="$MPV_LINK_ARGS -Wl,--version-script=$ROOT_DIR/scripts/libmpv.map"
MPV_LINK_ARGS="$MPV_LINK_ARGS -Wl,--gc-sections"
MPV_LINK_ARGS="$MPV_LINK_ARGS -Wl,--pack-dyn-relocs=relr"

# 关掉的三项（均已核实，勿轻易改回）：
#   egl-ohos  meson.build:1258 处它只带 video/out/opengl/context_ohos.c、
#             hwdec/hwdec_ohcodec_gl.c 与 egl_helpers.c，并置 features['gl']=true。
#             Vulkan 走独立分支 meson.build:1360（features['vulkan'] and features['ohos']
#             → video/out/vulkan/context_ohos.c），与 egl-ohos 不耦合。
#             消费方硬设 gpu-api=vulkan，故整条 GL 通路是死代码。
#   lua       消费方不使用 mpv 脚本。关掉后 scripts/lua.sh 也无需再构建。
#   lcms2     mpv 自己的 lcms2 选项 gate 着 video/out/gpu/lcms.c，与 libplacebo 的
#             lcms 选项是两回事，必须分别关。消费方未设 icc-profile。

# 已配置时走 --reconfigure，避免 Directory already configured。
# 改 built-in option（如 c_link_args）仍须 clean，见 BUILD-NOTES §5 陷阱 2。
setup_cmd=(meson setup)
[ -f build.ninja ] && setup_cmd+=(--reconfigure)
"${setup_cmd[@]}" .. \
  --cross-file $ROOT_DIR/libmpv/arm64-crossfile.ini \
  --prefix=$DEST/mpv \
  --default-library shared \
  --strip \
  -Dc_link_args="$MPV_LINK_ARGS" \
  -Dopensles=disabled \
  -Dohos=enabled \
  -Degl-ohos=disabled \
  -Dvulkan=enabled \
  -Dshaderc=enabled \
  -Dlua=disabled \
  -Dlcms2=disabled \
  -Dgpl=false \
  -Dbuild-date=false \
  -Dcplayer=false \
  -Dmanpage-build=disabled
ninja -j$CORES
ninja install

cd $DEST/mpv/lib
mv libmpv.so ../../libmpv.so

popd