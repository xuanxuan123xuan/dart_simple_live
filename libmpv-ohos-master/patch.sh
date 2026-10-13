#!/bin/bash

set -eu

PATCHES=(patches/*)
ROOT=$(pwd)

for dep_path in "${PATCHES[@]}"; do
  if [ -d "$dep_path" ]; then
    patches=($dep_path/*)
    dep=${dep_path#*/}
    pushd ./libmpv/$dep
    echo "Patching $dep..."
    for patch in "${patches[@]}"; do
      # 幂等：download-deps.sh 对已存在的依赖目录跳过下载，但补丁会被重放。
      # 不预判就重跑 bundle.sh 时，git apply 报 "patch does not apply" 并因
      # set -e 中断整个构建，只能手工 git checkout 各依赖目录才能恢复。
      #
      # --check 判「能否应用」，--reverse --check 判「是否已应用」。
      # 两者都失败才是真冲突：源码与补丁不匹配，必须停下，不能静默跳过。
      if git apply --check "$ROOT/$patch" 2>/dev/null; then
        echo "Applying $patch..."
        git apply "$ROOT/$patch"
      elif git apply --reverse --check "$ROOT/$patch" 2>/dev/null; then
        echo "Skipping $patch (already applied)..."
      else
        echo "ERROR: $patch neither applies nor is already applied." >&2
        echo "       The dependency source may be at an unexpected version." >&2
        exit 1
      fi
    done
    popd
  fi
done
