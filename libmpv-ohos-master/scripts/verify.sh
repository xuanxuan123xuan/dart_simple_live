#!/bin/bash

set -eu

ROOT_DIR=$(cd $(dirname "$0")/..; pwd)

. $ROOT_DIR/env.sh

# 符号差分靠 comm，而 comm 要求两侧按同一规则排序。sort 的顺序受 locale 影响，
# 记基线与比对时若 locale 不同会得出错误差集，故全程锁定 C。
export LC_ALL=C

# BUILD-NOTES §7「四项必查」的脚本化，另加第 5 项（未定义符号可解析性）。改任何编译/链接参数后跑：
#   ./scripts/verify.sh snapshot <name>   在改动前记基线
#   ./scripts/verify.sh check <name>      改动后对比，有回归则非零退出
#
# 为什么要两个产物：符号存活差分必须用**未 strip** 的，内部符号本就不在 .dynsym
# 里，拿 strip 后的产物扫描会给出大量假阴性（BUILD-NOTES §5 陷阱 3 踩过）。
# 未 strip 产物只在 ninja install 之前存在于构建树，install 时 meson 才 strip。

LLVM_BIN=$OHOS_NDK_HOME/native/llvm/bin
NM=$LLVM_BIN/llvm-nm
READELF=$LLVM_BIN/llvm-readelf

UNSTRIPPED=${UNSTRIPPED:-$ROOT_DIR/libmpv/mpv/.build/libmpv.so}
STRIPPED=${STRIPPED:-$DEST/libmpv.so}
BASELINE_DIR=$ROOT_DIR/baselines
CONSUMER_API=$ROOT_DIR/scripts/consumer-api.txt
# 第 5 项要拿系统库的导出面做「未定义符号能否解析」的判定。
SYSROOT_LIBS=${SYSROOT_LIBS:-$OHOS_NDK_HOME/native/sysroot/usr/lib/aarch64-linux-ohos}
CXX_SHARED=${CXX_SHARED:-$OHOS_NDK_HOME/native/llvm/lib/aarch64-linux-ohos/libc++_shared.so}

usage() {
  cat >&2 <<EOF
用法:
  $0 snapshot <name>   把当前产物记为基线，写入 baselines/<name>/
  $0 check <name>      对比当前产物与该基线，有回归则非零退出
  $0 report            只打印当前产物概况，不比对

环境变量:
  UNSTRIPPED  未 strip 产物 (默认 \$ROOT/libmpv/mpv/.build/libmpv.so)
  STRIPPED    已 strip 产物 (默认 \$DEST/libmpv.so)
  ALLOW_SKIP  设为 1 时，check 有跳过项也返回 0（默认返回 2）

check 的退出码:
  0  五项全过
  1  有失败项
  2  无失败项但有跳过项 —— 跳过不等于通过，这不是一次完整验证
EOF
  exit 1
}

# ---------- 采集 ----------

# 未 strip 产物的全部定义符号。这是「组件是否还活着」的唯一可靠仪器。
collect_defined_syms() {
  $NM --defined-only "$UNSTRIPPED" | awk '{print $NF}' | sort -u
}

# 导出面。消费方按 SONAME + $ORIGIN rpath dlopen，少一个 API 就是 ABI 事故。
collect_dyn_syms() {
  $NM -D --defined-only "$STRIPPED" | awk '{print $NF}' | sort -u
}

# SONAME 变了消费方 dlopen 会失败；DT_NEEDED 多出或少掉系统库会在应用
# namespace 里 reloc 失败，表现为 mpv_create not found。必须与基线完全一致。
collect_needed() {
  $READELF -d "$STRIPPED" \
    | grep -E '\((NEEDED|SONAME)\)' \
    | sed -E 's/.*\[(.*)\].*/\1/' \
    | sort
}

# 段号窄于 10 时 readelf 会输出 "[ 1] .text"，按空白切分会把 "1]" 当成段名，
# 故先剥掉 [Nr] 前缀再取字段：剥后依次是 Name Type Address Off Size ...
collect_sections() {
  $READELF -S --wide "$STRIPPED" \
    | sed -E 's/^ *\[ *[0-9]+\] *//' \
    | awk '$1 ~ /^\./ {print $1, $5}' \
    | sort
}

file_size() {
  stat -c %s "$1" 2>/dev/null || stat -f %z "$1"
}

sha256() {
  if command -v sha256sum > /dev/null; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

collect_summary() {
  echo "size_bytes $(file_size "$STRIPPED")"
  echo "gzip9_bytes $(gzip -9 -c "$STRIPPED" | wc -c)"
  echo "sha256 $(sha256 "$STRIPPED")"
}

require_stripped() {
  [ -f "$STRIPPED" ] || { echo "找不到已 strip 产物: $STRIPPED" >&2; exit 1; }
}

# ---------- 五项必查 ----------

fails=0
skips=0
fail() { echo "  FAIL  $*"; fails=$((fails + 1)); }
pass() { echo "  ok    $*"; }
# 跳过必须单独计数：跳过不等于通过。第 1 项（符号存活差分）依赖未 strip 产物，
# 而它只在 ninja install 之前存在——若把跳过算作通过，最敏感的一项静默失效
# 却仍打印「全过」，比不检查更危险。
skip() { echo "  skip  $*"; skips=$((skips + 1)); }

# 第 4 项：已 strip。放最前面，因为后面几项都假设产物是最终形态。
check_stripped() {
  echo "[4/5] strip 确认"
  local n
  n=$($READELF -S --wide "$STRIPPED" | grep -cE '\.symtab|\.debug_' || true)
  if [ "$n" -ne 0 ]; then
    fail ".symtab / .debug_* 仍存在（$n 个段），ninja install 的 --strip 没生效"
  else
    pass "无 .symtab / .debug_*"
  fi
}

# 第 1 项：registry 存活差分。只看变体自己有没有某符号是无意义的（探针名可能本来就写错），
# 必须做「基线有、变体没了」的差集。
check_defined_syms() {
  local base=$1
  echo "[1/5] 定义符号存活差分（未 strip）"
  if [ ! -f "$UNSTRIPPED" ]; then
    skip "未 strip 产物不存在: $UNSTRIPPED"
    echo "        （ninja install 后会被 strip，需在 install 前跑 snapshot/check）"
    return
  fi
  if [ ! -s "$base/defined-syms.txt" ]; then
    skip "基线 $(basename "$base") 没有定义符号快照，本项无法比对"
    echo "        （两种可能：记基线时未 strip 产物不存在；或这是历史基线，"
    echo "          它那份 2 MB 的符号清单已被裁剪以免撑大仓库——"
    echo "          只有本轮起点与最新基线保留完整快照，见 OPTIMIZATION-STATUS.md §4.3）"
    return
  fi
  local cur lost
  cur=$(mktemp); collect_defined_syms > "$cur"
  lost=$(comm -23 "$base/defined-syms.txt" "$cur" || true)
  echo "  基线 $(wc -l < "$base/defined-syms.txt") → 当前 $(wc -l < "$cur")"
  if [ -n "$lost" ]; then
    fail "以下符号在基线有、当前没了（前 40 条）:"
    echo "$lost" | head -40 | sed 's/^/          /'
    echo "        共 $(echo "$lost" | wc -l) 条，完整清单: $cur"
  else
    pass "无符号丢失"
  fi
}

# 第 2 项：导出面。两道检查：
#   a) 消费方实际调用的 API 逐个校验（scripts/consumer-api.txt）——这是硬性底线，
#      不依赖基线，即使基线本身出问题也能兜住。
#   b) 与基线做 mpv_* 差集，捕捉基线里有而当前没有的其余导出。
check_dyn_syms() {
  local base=$1
  echo "[2/5] 导出面"
  local cur lost n_base n_cur
  cur=$(mktemp); collect_dyn_syms > "$cur"

  if [ -f "$CONSUMER_API" ]; then
    local want missing=0 n=0
    while read -r want; do
      # 防御性剥掉 \r。.gitattributes 已经把落盘钉成 LF，但手工编辑或跨平台拷贝
      # 仍可能带回 CRLF，那会让每个名字尾部多一个 \r、grep -qx 全部落空，
      # 把「19 个 API 齐全」误报成「19 个全缺失」——假警报比不检查更糟。
      want=${want%$'\r'}
      case "$want" in ''|\#*) continue ;; esac
      n=$((n + 1))
      grep -qx "$want" "$cur" || { echo "          缺失: $want"; missing=$((missing + 1)); }
    done < "$CONSUMER_API"
    if [ "$missing" -ne 0 ]; then
      fail "消费方调用的 $n 个 API 中缺失 $missing 个（ABI 事故）"
    else
      pass "消费方调用的 $n 个 API 全部在导出面里"
    fi
  else
    skip "找不到 $CONSUMER_API，跳过消费方 API 校验"
  fi

  n_base=$(grep -c '^mpv_' "$base/dyn-syms.txt" || true)
  n_cur=$(grep -c '^mpv_' "$cur" || true)
  echo "  mpv_* 基线 $n_base → 当前 $n_cur"
  lost=$(comm -23 <(grep '^mpv_' "$base/dyn-syms.txt" | sort) <(grep '^mpv_' "$cur" | sort) || true)
  if [ -n "$lost" ]; then
    fail "以下导出符号相对基线丢失:"
    echo "$lost" | sed 's/^/          /'
  else
    pass "导出面相对基线无缺失"
  fi
  # 导出面不该反向膨胀，否则说明 version script 没生效
  if [ "$(wc -l < "$cur")" -gt "$(( $(wc -l < "$base/dyn-syms.txt") + 16 ))" ]; then
    fail "导出符号数明显多于基线（$(wc -l < "$base/dyn-syms.txt") → $(wc -l < "$cur")），检查 version script 是否生效"
  fi
}

# 第 5 项：未定义符号可解析性。不依赖基线，是绝对判据。
#
# 共享库允许留下未定义符号交给加载时解析，所以「链接通过」根本不等于「能加载」。
# 本项目为此付出过一次代价：关掉 -Degl-ohos 后，mpv 的 hwdec_ohcodec.c 仍然引用
# ohcodec_interop_gl_init——它那个 #if 用的是 HAVE_GL，而定义所在的
# hwdec_ohcodec_gl.c 只在 egl-ohos 打开时才编译，两个 gate 不一致。
# 构建全程无警告，前四项检查也全过，直到设备上 dlopen 时 reloc 失败，
# 报的还是毫不相关的 "Load native module failed"。
# 这类故障只有在这里才拦得住，故列为硬性失败项。
check_undefined() {
  echo "[5/5] 未定义符号可解析性"
  if [ ! -d "$SYSROOT_LIBS" ]; then
    skip "找不到 sysroot 库目录: $SYSROOT_LIBS"
    return
  fi
  local undef sysexp unresolved
  undef=$(mktemp); sysexp=$(mktemp)
  # 只取强未定义（nm 标 U）。弱未定义（w / v）允许无人提供，加载器把它解析成 0，
  # 不会 reloc 失败——本产物里 __at_fini 与 __register_frame_info 系列正是这种，
  # 不过滤就会稳定误报四条，而会哭狼的检查等于没有检查。
  $NM -D --undefined-only "$STRIPPED" | awk '$1 == "U" {print $2}' | sort -u > "$undef"
  # 把 sysroot 全部桩库连同 libc++_shared 一起当作可解析来源。宁可放宽也不误报：
  # 目标是抓「谁都不提供」的悬空符号，不是精确复现加载器的查找顺序。
  $NM -D --defined-only "$SYSROOT_LIBS"/*.so 2>/dev/null | awk '{print $NF}' > "$sysexp"
  [ -f "$CXX_SHARED" ] && $NM -D --defined-only "$CXX_SHARED" 2>/dev/null | awk '{print $NF}' >> "$sysexp"
  sort -u "$sysexp" -o "$sysexp"
  unresolved=$(comm -23 "$undef" "$sysexp" || true)
  if [ -n "$unresolved" ]; then
    fail "以下未定义符号在 NDK 系统库里找不到提供者，设备上 dlopen 必然 reloc 失败:"
    echo "$unresolved" | sed 's/^/          /'
  else
    pass "$(wc -l < "$undef") 个强未定义符号全部可由系统库解析"
  fi
}

# 第 3 项：SONAME 与 DT_NEEDED 必须完全一致。
check_needed() {
  local base=$1
  echo "[3/5] SONAME 与 DT_NEEDED"
  local cur n_soname
  cur=$(mktemp); collect_needed > "$cur"
  # SONAME 与 DT_NEEDED 在 needed.txt 里混排，直接报行数会让人把 SONAME 也数成一个
  # 依赖库——文档里已经因此把 11 个 DT_NEEDED 抄成 12 个，故分开报。
  n_soname=$($READELF -d "$STRIPPED" | grep -cE '\(SONAME\)' || true)
  if diff -u "$base/needed.txt" "$cur" > /dev/null; then
    pass "SONAME + $(( $(wc -l < "$cur") - n_soname )) 个 DT_NEEDED，与基线一致"
  else
    fail "与基线不一致:"
    diff -u "$base/needed.txt" "$cur" | sed 's/^/          /' || true
  fi
}

# 段级增减。不参与成败判定——段表本身不是正确性指标，但每次体积改动都要做段级归因
# （.text 掉了多少、.rodata 掉了多少），此前 snapshot 采了 sections.txt 却没有任何
# 地方读它，属于只写不读的死数据。
# collect_sections 存的是 readelf 的十六进制 Size，故用 $((16#..)) 转十进制再相减；
# 不用 awk 是因为 mawk 没有 strtonum，WSL 上默认 awk 未必是 gawk。
report_sections() {
  local base=$1
  [ -s "$base/sections.txt" ] || return 0
  local cur name hex bhex changed=0
  cur=$(mktemp); collect_sections > "$cur"
  echo "[段级差异]（体积归因用，不判定成败）"
  while read -r name hex; do
    bhex=$(awk -v n="$name" '$1 == n { print $2; exit }' "$base/sections.txt")
    if [ -z "$bhex" ]; then
      printf '  %-22s %14s → %14d  新增\n' "$name" "-" "$((16#$hex))"
      changed=1
    elif [ "$bhex" != "$hex" ]; then
      printf '  %-22s %14d → %14d  %+d\n' \
        "$name" "$((16#$bhex))" "$((16#$hex))" "$((16#$hex - 16#$bhex))"
      changed=1
    fi
  done < "$cur"
  while read -r name hex; do
    if ! awk -v n="$name" '$1 == n { f = 1 } END { exit !f }' "$cur"; then
      printf '  %-22s %14d → %14s  消失\n' "$name" "$((16#$hex))" "-"
      changed=1
    fi
  done < "$base/sections.txt"
  [ "$changed" -ne 0 ] || echo "  与基线完全一致"
  return 0
}

report_size() {
  local base=${1:-}
  echo "[体积]"
  local size gz
  size=$(file_size "$STRIPPED")
  gz=$(gzip -9 -c "$STRIPPED" | wc -c)
  printf '  当前  %s (%.2f MiB)  gzip -9 %s (%.2f MiB)\n' \
    "$size" "$(echo "$size" | awk '{print $1/1048576}')" \
    "$gz" "$(echo "$gz" | awk '{print $1/1048576}')"
  if [ -n "$base" ] && [ -f "$base/summary.txt" ]; then
    local bsize bgz
    bsize=$(awk '$1=="size_bytes"{print $2}' "$base/summary.txt")
    bgz=$(awk '$1=="gzip9_bytes"{print $2}' "$base/summary.txt")
    printf '  基线  %s (%.2f MiB)  gzip -9 %s (%.2f MiB)\n' \
      "$bsize" "$(echo "$bsize" | awk '{print $1/1048576}')" \
      "$bgz" "$(echo "$bgz" | awk '{print $1/1048576}')"
    printf '  差值  %+d bytes (%+.2f MiB)  gzip %+d bytes (%+.2f MiB)\n' \
      "$((size - bsize))" "$(echo "$size $bsize" | awk '{print ($1-$2)/1048576}')" \
      "$((gz - bgz))" "$(echo "$gz $bgz" | awk '{print ($1-$2)/1048576}')"
  fi
}

# ---------- 入口 ----------

cmd=${1:-}
name=${2:-}

case "$cmd" in
  snapshot)
    [ -n "$name" ] || usage
    require_stripped
    out=$BASELINE_DIR/$name
    mkdir -p "$out"
    collect_dyn_syms  > "$out/dyn-syms.txt"
    collect_needed    > "$out/needed.txt"
    collect_sections  > "$out/sections.txt"
    collect_summary   > "$out/summary.txt"
    if [ -f "$UNSTRIPPED" ]; then
      collect_defined_syms > "$out/defined-syms.txt"
    else
      echo "警告: 未 strip 产物不存在，本基线缺少定义符号快照，check 时第 1 项会被跳过" >&2
      : > "$out/defined-syms.txt"
    fi
    echo "基线已写入 $out"
    report_size
    ;;

  check)
    [ -n "$name" ] || usage
    require_stripped
    base=$BASELINE_DIR/$name
    [ -d "$base" ] || { echo "找不到基线: $base（先跑 snapshot）" >&2; exit 1; }
    echo "对比基线: $name"
    echo
    check_stripped
    check_defined_syms "$base"
    check_dyn_syms "$base"
    check_needed "$base"
    check_undefined
    echo
    report_sections "$base"
    echo
    report_size "$base"
    echo
    if [ "$fails" -ne 0 ]; then
      echo "结果: $fails 项失败"
      exit 1
    fi
    if [ "$skips" -eq 0 ]; then
      echo "结果: 五项全过"
      exit 0
    fi
    echo "结果: 无失败项，但有 $skips 项被跳过 —— 这不是一次完整验证。"
    echo "      常见原因：第 1 项需要未 strip 产物（只在 ninja install 之前存在），"
    echo "      或比对的是符号快照已被裁剪的历史基线。逐项输出里有具体说明。"
    if [ "${ALLOW_SKIP:-0}" = "1" ]; then
      echo "      ALLOW_SKIP=1，按通过处理。"
      exit 0
    fi
    echo "      确认可以接受后用 ALLOW_SKIP=1 重跑，即可取得零退出码。"
    exit 2
    ;;

  report)
    require_stripped
    check_stripped
    # 未定义符号可解析性不依赖基线，report 里也跑——它是「这个产物能不能被 dlopen」
    # 的最快判据，值得在冒烟阶段就看到。
    check_undefined
    echo
    echo "[导出面] mpv_* $(collect_dyn_syms | grep -c '^mpv_' || true) / 全部 $(collect_dyn_syms | wc -l)"
    echo "[SONAME + DT_NEEDED]"
    collect_needed | sed 's/^/  /'
    echo
    report_size
    [ "$fails" -eq 0 ] || exit 1
    ;;

  *)
    usage
    ;;
esac
