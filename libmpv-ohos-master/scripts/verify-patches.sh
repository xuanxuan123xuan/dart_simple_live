#!/bin/bash

set -eu

ROOT_DIR=$(cd $(dirname "$0")/..; pwd)

# 校验 patches/ 下每个 hunk 头与实际内容是否自洽，两类检查：
#
#   1. 行数：hunk 头声明的旧/新行数，与 hunk 里实际的 -/+/上下文行数是否相符。
#   2. 起始行：新侧起始行 = 旧侧起始行 + 本文件前面各 hunk 造成的行数净增量。
#
# 为什么需要：BUILD-NOTES §10 的同步流程只覆盖「从构建副本 git diff 导出」，
# 没覆盖「手工编辑 patch 文件」——而后者最容易改了内容却忘了改 hunk 头。
# 提交 48fc3e1 就这样把 support-external-yuv-zero-copy.patch 的
# @@ -672,7 +678,8 @@ 留在了实际 10 行的 hunk 上，导致从 HEAD 做干净构建
# 在 patch.sh 阶段直接失败。
#
# 第 2 类是同一事故的另一种形态：改了某个 hunk 的行数、也改了它自己的头，
# 却忘了顺延同一文件后续 hunk 的起始行。git apply 靠上下文搜索能容忍这种偏移，
# 所以它未必当场失败，但补丁已经不再自洽，换个工具或换个版本就可能炸。
#
# git apply 遇到第 1 类报的是 "corrupt patch at line 205"，而 205 指向的是
# **下一个文件**的 diff 头，极具误导性。本脚本直接指出是哪个 hunk、差多少。
#
# 相比 git apply --check 的优势：不需要依赖源码已下载，任何时候都能跑，
# 适合放进 CI 或手改 patch 之后立即自查。

usage() {
  echo "用法: $0 [patch 文件...]   (默认检查 patches/*/*.patch)" >&2
  exit 1
}

[ "${1:-}" = "-h" ] && usage

cd "$ROOT_DIR"

if [ $# -gt 0 ]; then
  patches=("$@")
else
  shopt -s nullglob
  patches=(patches/*/*.patch)
  shopt -u nullglob
fi

if [ ${#patches[@]} -eq 0 ]; then
  echo "没有找到任何 patch 文件" >&2
  exit 1
fi

fails=0
total_hunks=0

for p in "${patches[@]}"; do
  [ -f "$p" ] || { echo "FAIL  $p 不存在"; fails=$((fails + 1)); continue; }

  out=$(awk -v F="$p" '
    function flush(reason,   _) {
      if (!in_hunk) return
      printf "  %s:%d  %s\n", F, hline, reason
      printf "        %s\n", hdr
      printf "        声明 旧 %d 行 / 新 %d 行，实际 旧 %d 行 / 新 %d 行\n",
             wantold, wantnew, oldc, newc
      bad++
      in_hunk = 0
    }

    # 文件边界：git 风格的补丁有 diff --git，纯 unified diff（本仓 patches/mpv/ 两个）
    # 只有 --- / +++，故两者都当边界，累计偏移在此清零。
    function newfile(   _) {
      flush("hunk 提前结束（行数不足）")
      cum = 0; oldc = 0; newc = 0
    }

    function setname(s) { sub(/^[ab]\//, "", s); fname = s }

    /^diff --git/ { newfile(); setname($3); next }
    /^--- /       { newfile(); if ($2 != "/dev/null") setname($2); next }
    /^\+\+\+ /    { newfile(); if ($2 != "/dev/null") setname($2); next }
    /^index /     { flush("hunk 提前结束（行数不足）"); next }

    /^@@/ {
      flush("hunk 提前结束（行数不足）")

      # 用上一个 hunk 的**实际**行数推进累计偏移，而不是它声明的行数：
      # 这样即便某个 hunk 的声明是错的（第 1 类问题），起始行判断仍然有效，
      # 两类错误不会互相污染成一串噪声。文件边界处已清零。
      cum += (newc - oldc)

      # 解析 @@ -a,b +c,d @@，省略 ,b 时计数为 1
      split($2, o, ","); split($3, n, ",")
      oldstart = -(o[1] + 0); newstart = n[1] + 0
      wantold = (length(o) > 1) ? o[2] + 0 : 1
      wantnew = (length(n) > 1) ? n[2] + 0 : 1

      # 新增文件是 -0,0，删除文件是 +0,0，两者的起始行不参与推算。
      if (oldstart > 0 && newstart > 0 && newstart != oldstart + cum) {
        printf "  %s:%d  hunk 起始行与累计偏移不符\n", F, FNR
        printf "        %s\n", $0
        printf "        %s：前面各 hunk 令新侧净增 %+d 行，故新起始应为 %d，实际 %d\n",
               fname, cum, oldstart + cum, newstart
        bad++
      }

      hdr = $0; hline = FNR; oldc = 0; newc = 0; in_hunk = 1; hunks++
      next
    }

    in_hunk {
      c = substr($0, 1, 1)
      # "\ No newline at end of file" 不计入任何一侧
      if (c == "\\") next
      # 空行按上下文处理：部分工具会把纯空白的上下文行的尾随空格删掉
      if (c == " " || $0 == "") { oldc++; newc++ }
      else if (c == "-")        { oldc++ }
      else if (c == "+")        { newc++ }
      else { flush("hunk 中出现非法行首字符 \"" c "\""); next }

      # 两侧都达标即认为 hunk 结束，此时若与声明不符就是行数错误
      if (oldc >= wantold && newc >= wantnew) {
        if (oldc != wantold || newc != wantnew)
          flush("hunk 行数与声明不符")
        else
          in_hunk = 0
      }
    }

    END {
      flush("hunk 提前结束（文件结尾）")
      printf "@@COUNT %d %d\n", hunks, bad
    }
  ' "$p")

  count_line=$(echo "$out" | grep '^@@COUNT' || echo "@@COUNT 0 0")
  hunks=$(echo "$count_line" | awk '{print $2}')
  bad=$(echo "$count_line" | awk '{print $3}')
  body=$(echo "$out" | grep -v '^@@COUNT' || true)

  total_hunks=$((total_hunks + hunks))

  if [ "$bad" -gt 0 ]; then
    echo "FAIL  $p  ($hunks 个 hunk，$bad 个有问题)"
    echo "$body"
    fails=$((fails + bad))
  else
    printf 'ok    %-58s %2d 个 hunk\n' "$p" "$hunks"
  fi
done

echo
echo "共 ${#patches[@]} 个 patch，$total_hunks 个 hunk"
if [ "$fails" -ne 0 ]; then
  echo "结果: $fails 处不自洽"
  echo "提示: 手工改过 patch 内容后，hunk 头 @@ -旧起始,旧行数 +新起始,新行数 @@ 的四个数都要跟着改——"
  echo "      行数改了，同一文件后续 hunk 的新侧起始行也要顺延同样的增量。"
  exit 1
fi
echo "结果: 全部自洽（行数 + 起始行偏移）"
