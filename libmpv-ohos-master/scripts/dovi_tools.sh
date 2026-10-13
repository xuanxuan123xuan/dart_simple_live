#!/bin/bash

set -eu

ROOT_DIR=$(cd $(dirname "$0")/..; pwd)

. $ROOT_DIR/env.sh

pushd $ROOT_DIR/libmpv/dovi_tools/dolby_vision

if [ "${1:-}" == "build" ]; then
	echo -e "\nBuilding dovi tools..."
elif [ "${1:-}" == "clean" ]; then
	cargo clean
	exit 0
else
	echo "Usage: $0 {build|clean}" >&2
	exit 1
fi

cargo cinstall \
  --release \
  --target=aarch64-unknown-linux-ohos \
  --library-type=staticlib \
  --prefix=$DEST \
  --libdir=lib

popd
