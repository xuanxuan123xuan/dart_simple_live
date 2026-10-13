#!/bin/bash

set -eu

if command -v rustup &> /dev/null; then
  echo "rustup is already installed"
else
  echo "Installing rustup..."
  # 非 tty（CI / 干净 WSL）下 rustup-init 需要 -y；装完后当前 shell PATH
  # 不含 ~/.cargo/bin，必须显式导出，否则下一行 rustup target add 会 command not found。
  wget -qO - https://sh.rustup.rs | sh -s -- -y --no-modify-path
  export PATH="$HOME/.cargo/bin:$PATH"
fi

# 已安装 rustup 但 PATH 未含 cargo 时同样补上（例如 sourcing 不全的环境）。
if ! command -v rustup &> /dev/null; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi

rustup target add aarch64-unknown-linux-ohos
cargo install cargo-c --features=vendored-openssl
