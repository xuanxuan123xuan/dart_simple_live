#!/bin/bash

set -eu

ROOT_DIR=$(cd $(dirname "$0")/..; pwd)

. $ROOT_DIR/env.sh

pushd $ROOT_DIR/libmpv/mbedtls

if [ "${1:-}" == "build" ]; then
	echo -e "\nBuilding mbedtls..."
elif [ "${1:-}" == "clean" ]; then
	make clean
	exit 0
else
	echo "Usage: $0 {build|clean}" >&2
	exit 1
fi

python3 -m venv .venv
source .venv/bin/activate
pip install -r scripts/basic.requirements.txt

# mbedtls 的 library/Makefile 写的是 `CFLAGS ?= -O2`，编译规则为
# `$(CC) $(LOCAL_CFLAGS) $(CFLAGS) -c`，根 Makefile 不碰 CFLAGS。
# 也就是说 env.sh 一旦导出 CFLAGS，那个默认的 -O2 就永远不会生效——
# 整个 TLS/crypto 栈会退化成 -O0 编译（clang 无 -O 参数时的默认值），
# 影响 HTTPS / RTMPS / HLS-over-TLS 的握手与吞吐，同时白白撑大 .text。
# 故在此显式补回。用 -O2 而非 -O3 是跟随上游默认：mbedtls 的常量时间实现
# 按 -O2 做验证，拔高优化等级有让编译器破坏常量时间性质的先例。
export CFLAGS="$CFLAGS -O2"

make -j$CORES no_test
make DESTDIR=$DEST install

popd