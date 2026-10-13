#!/bin/bash

set -eu

ROOT_DIR=$(cd $(dirname "$0")/..; pwd)

. $ROOT_DIR/env.sh

pushd $ROOT_DIR/libmpv/lcms

if [ "${1:-}" == "build" ]; then
	echo -e "\nBuilding lcms..."
elif [ "${1:-}" == "clean" ]; then
	rm -rf .build
	exit 0
else
	echo "Usage: $0 {build|clean}" >&2
	exit 1
fi

mkdir -p .build
cd .build

# 已配置时走 --reconfigure，避免 Directory already configured。
# 改 built-in option（如 c_link_args）仍须 clean，见 BUILD-NOTES §5 陷阱 2。
setup_cmd=(meson setup)
[ -f build.ninja ] && setup_cmd+=(--reconfigure)
"${setup_cmd[@]}" .. \
  --cross-file $ROOT_DIR/libmpv/arm64-crossfile.ini \
  --prefix=$DEST \
  -Dtests=disabled
ninja -j$CORES
ninja install

popd