#!/bin/bash

set -eu

mkdir -p ./libmpv/arm64-build

if [ "$(uname -s)" = "Linux" ]; then
  if [ ! -d /sdk ]; then
    echo "Downloading OpenHarmony SDK..."
    ./download/download-sdk.sh
  fi
  # crossfile 软链每次都重建：复用已有 /sdk 或删掉 libmpv/ 重来时
  # 不能依赖「仅首次下载 SDK」分支，否则 --cross-file 指向不存在的路径。
  ln -sf ../crossfiles/arm64-crossfile-linux.ini ./libmpv/arm64-crossfile.ini
elif [ "$(uname -s)" = "Darwin" ]; then
  echo "Using DevEco Studio for macOS, please make sure DevEco Studio is installed."
  ln -sf ../crossfiles/arm64-crossfile-macos.ini ./libmpv/arm64-crossfile.ini
else
  echo "Unsupported platform." >&2
  exit 1
fi

# OHOS Rust 工具链只服务 dovi_tools（libdovi，Rust 实现），而 libplacebo 已关掉 dovi。
# 若改回 -Ddovi=enabled，需把下一行取消注释，并在 build.sh 里加回 dovi_tools.sh。
# ./download/download-ohos-rs.sh
./download/download-deps.sh
