#!/bin/bash

# ============================================================
# Nezuko Kernel build script - RMX2061 (atoll) + BakaSU
# ============================================================

# Pindah ke root source (lokasi script ini)
KERNEL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$KERNEL_ROOT" || exit 1
export KERNEL_ROOT

# ---------------------[ Konfigurasi ]---------------------
KERNEL_NAME="Nezuko"
DEVICE="RMX2061"
VARIANT="perf"
VERSION_NUMBER="v1"

# KSU: 1 = pasang BakaSU, 0 = build kontrol TANPA root (untuk uji bootloop)
ENABLE_KSU="${ENABLE_KSU:-1}"

# Versi BakaSU yang di-clone: main, atau tag v4.2.0-rc1 / rc2 / rc3.
# JANGAN pakai tag lama (<= v4.1.0): masih era SukiSU-Ultra, manual hook non-aktif.
BAKASU_REF="${BAKASU_REF:-main}"

# Jaga-jaga: kalau nilai kosong atau salah ketik, pakai main
case "$BAKASU_REF" in
  main|v[0-9]*.[0-9]*) ;;
  *)
    echo "⚠️  BAKASU_REF tidak valid ('$BAKASU_REF'), memakai main"
    BAKASU_REF="main"
    ;;
esac

if [ "$ENABLE_KSU" = "1" ]; then
  BUILD_TYPE="BakaSU-${BAKASU_REF}"
else
  BUILD_TYPE="NoKSU"
fi

# Nama defconfig. Kosongkan untuk deteksi otomatis.
DEFCONFIG="${DEFCONFIG:-}"

# SUSFS: 0 = mati (disarankan sampai BakaSU saja sudah boot), 1 = hidup
ENABLE_SUSFS="${ENABLE_SUSFS:-0}"

# DEBUG: 1 = ubah hang/lockup menjadi panic supaya tercatat di pstore (ramoops)
# (sementara 1 untuk build diagnostik; kembalikan ke 0 setelah BakaSU berhasil boot)
ENABLE_DEBUG="${ENABLE_DEBUG:-1}"

# CFI: 1 = matikan CFI + ShadowCallStack (uji kompatibilitas BakaSU dengan kernel 4.14 ini)
DISABLE_CFI="${DISABLE_CFI:-1}"

KERNEL_STRING="Nezuko BakaSU | RMX2061"
FLASH_MESSAGE="Nezuko BakaSU flashed successfully!"

# ---------------------[ Path ]---------------------
CLANG_DIR="$HOME/toolchains/clang"
GCC_DIR="$HOME/toolchains/gcc-aarch64-linux-gnu-9.3"
ANYKERNEL_DIR="$HOME/AnyKernel3"
OUT_DIR="out"

DATE=$(date +%Y%m%d)
TIME=$(date +%H%M)
BASE_ZIPNAME="${KERNEL_NAME}-${VARIANT}-${DEVICE}-${BUILD_TYPE}-${TIME}-${DATE}-${VERSION_NUMBER}"
ZIPNAME="${BASE_ZIPNAME}.zip"

JOBS="${JOBS:-$(nproc)}"

die() {
  echo -e "\n❌ \033[1;31m$*\033[0m"
  exit 1
}

# ============================================================
# Toolchain dan AnyKernel3
# ============================================================
mkdir -p "$HOME/toolchains"

if [ ! -x "$CLANG_DIR/bin/clang" ]; then
  echo -e "\n🔍 \033[1;33mClang toolchain not found. Cloning...\033[0m"
  rm -rf "$CLANG_DIR"
  git clone --depth=1 --branch lineage-20.0 \
    https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b.git \
    "$CLANG_DIR" || die "Failed to clone Clang."
else
  echo -e "\n✅ \033[1;32mClang toolchain already present.\033[0m"
fi

if [ ! -x "$GCC_DIR/bin/aarch64-linux-gcc" ]; then
  echo -e "\n🔍 \033[1;33mGCC toolchain not found. Cloning...\033[0m"
  rm -rf "$GCC_DIR"
  git clone --depth=1 --branch lineage-23.0 \
    https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-9.3.git \
    "$GCC_DIR" || die "Failed to clone GCC."
else
  echo -e "\n✅ \033[1;32mGCC toolchain already present.\033[0m"
fi

if [ ! -f "$ANYKERNEL_DIR/tools/ak3-core.sh" ]; then
  echo -e "\n🔍 \033[1;33mAnyKernel3 not found. Cloning...\033[0m"
  rm -rf "$ANYKERNEL_DIR"
  git clone --depth=1 https://github.com/theshaenix/AnyKernel3.git \
    "$ANYKERNEL_DIR" || die "Failed to clone AnyKernel3."
else
  echo -e "\n✅ \033[1;32mAnyKernel3 folder already present.\033[0m"
fi

# Pakai anykernel.sh milik repo kernel ini (ak3/anykernel.sh) jika ada,
# supaya tidak bergantung pada repo AnyKernel3 pihak ketiga.
if [ -f "$KERNEL_ROOT/ak3/anykernel.sh" ]; then
  cp "$KERNEL_ROOT/ak3/anykernel.sh" "$ANYKERNEL_DIR/anykernel.sh"
  echo -e "\n✅ \033[1;32mMemakai ak3/anykernel.sh dari repo kernel.\033[0m"
fi

# ---------------------[ AnyKernel branding ]---------------------
echo -e "\n✏️  \033[1;36mUpdating AnyKernel branding...\033[0m"

if [ -f "$ANYKERNEL_DIR/anykernel.sh" ]; then
  # Pemisah '#' supaya karakter '|' di teks tidak merusak sed
  sed -i "s#^kernel.string=.*#kernel.string=${KERNEL_STRING}#" "$ANYKERNEL_DIR/anykernel.sh"
  sed -i "s#Ka-chow!.*McQueen is ready to race.#${FLASH_MESSAGE}#" "$ANYKERNEL_DIR/anykernel.sh"
  echo -e "✅ kernel.string  → ${KERNEL_STRING}"
  echo -e "✅ flash message  → ${FLASH_MESSAGE}"
else
  echo -e "⚠️  anykernel.sh not found"
fi

# ============================================================
# Setup BakaSU
# ============================================================
if [ "$ENABLE_KSU" = "1" ]; then
  echo -e "\n🔥 \033[1;35mSetting up BakaSU...\033[0m"

  rm -rf drivers/kernelsu KernelSU
  if [ "$BAKASU_REF" = "main" ]; then
    git clone --depth=1 --branch main https://github.com/Baka-SU/BakaSU.git KernelSU \
      || die "Failed to clone BakaSU (ref: main)."
  else
    # Tag: clone penuh (dengan riwayat git) karena Kbuild BakaSU membaca git history
    git clone --branch "$BAKASU_REF" https://github.com/Baka-SU/BakaSU.git KernelSU \
      || die "Failed to clone BakaSU (ref: $BAKASU_REF)."
  fi
  echo -e "ℹ️  BakaSU ref: $BAKASU_REF ($(git -C KernelSU rev-parse --short HEAD))"
  ln -sf ../KernelSU/kernel drivers/kernelsu

  if ! grep -q "kernelsu" drivers/Makefile; then
    echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile
  fi

  if ! grep -q "kernelsu" drivers/Kconfig; then
    sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' drivers/Kconfig
  fi

  echo -e "✅ BakaSU ready"
else
  echo -e "\n⏭️  \033[1;33mENABLE_KSU=0: BakaSU dilewati (build kontrol).\033[0m"
fi

# ============================================================
# Environment
# ============================================================
export ARCH=arm64
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-
export PATH="$CLANG_DIR/bin:$GCC_DIR/bin:$PATH"

# Pastikan yang dipakai adalah toolchain kita, bukan clang bawaan runner
case "$(command -v clang)" in
  "$CLANG_DIR"/*) ;;
  *) die "Clang yang terpakai bukan toolchain: $(command -v clang). Hapus cache toolchain di GitHub Actions." ;;
esac
command -v "${CROSS_COMPILE}gcc" > /dev/null 2>&1 \
  || die "${CROSS_COMPILE}gcc tidak ditemukan di $GCC_DIR/bin. Hapus cache toolchain di GitHub Actions."

if command -v ccache > /dev/null 2>&1; then
  CC_CMD="ccache clang"
else
  CC_CMD="clang"
fi

show_first_failure_context() {
  local failure_line context_start context_end

  failure_line=$(grep -n -m1 -E \
    '(^|: )(fatal )?error:|fatal:|clang:.*(unable|crash)|make(\[[0-9]+\])?: \*\*\*' \
    "$OUT_DIR/build.log" | cut -d: -f1)

  if [ -n "$failure_line" ]; then
    context_start=$((failure_line > 40 ? failure_line - 40 : 1))
    context_end=$((failure_line + 20))
    echo -e "\n🔎 \033[1;36mFirst failure context from $OUT_DIR/build.log:\033[0m"
    sed -n "${context_start},${context_end}p" "$OUT_DIR/build.log"
  fi
}

# ============================================================
# Start
# ============================================================
echo -e "\n🛠️  \033[1;34mStarting Kernel Build: $BASE_ZIPNAME\033[0m"

echo -e "\n🧹 \033[1;33mCleaning output...\033[0m"
rm -rf "${OUT_DIR:?}"/*
mkdir -p "$OUT_DIR"
rm -f "$ANYKERNEL_DIR/zImage" "$ANYKERNEL_DIR"/*.zip

echo -e "\n🔧 \033[1;36mCompiler Info:\033[0m"
clang --version | head -n 1
"${CROSS_COMPILE}gcc" --version | head -n 1

echo -e "\n📱 \033[1;32mTarget Device: $DEVICE\033[0m"
echo -e "🧵 \033[1;36mParallel build jobs: $JOBS\033[0m"

# ============================================================
# Defconfig
# ============================================================
if [ -z "$DEFCONFIG" ]; then
  for candidate in atoll_defconfig vendor/atoll-perf_defconfig vendor/atoll_defconfig; do
    if [ -f "arch/arm64/configs/$candidate" ]; then
      DEFCONFIG="$candidate"
      break
    fi
  done
fi

if [ -z "$DEFCONFIG" ] || [ ! -f "arch/arm64/configs/$DEFCONFIG" ]; then
  echo "Defconfig tersedia (atoll):"
  find arch/arm64/configs -name '*atoll*' 2>/dev/null
  die "Defconfig tidak ditemukan. Set variabel DEFCONFIG di script ini."
fi

echo -e "\n📄 \033[1;36mSetting up defconfig: $DEFCONFIG\033[0m"
make O="$OUT_DIR" ARCH=arm64 LLVM=1 LLVM_IAS=1 "$DEFCONFIG" \
  || die "Defconfig failed. Exiting."

# ============================================================
# Enable BakaSU (+ SUSFS opsional)
# ============================================================
CFG="./scripts/config --file $OUT_DIR/.config"

if [ "$DISABLE_CFI" = "1" ]; then
  echo -e "\n🧪 \033[1;33mDISABLE_CFI=1: matikan CFI + ShadowCallStack...\033[0m"
  $CFG --disable CONFIG_CFI_PERMISSIVE
  $CFG --disable CONFIG_CFI_CLANG
  $CFG --disable CONFIG_SHADOW_CALL_STACK
  BUILD_TYPE="${BUILD_TYPE}-NoCFI"
  ZIPNAME="${KERNEL_NAME}-${VARIANT}-${DEVICE}-${BUILD_TYPE}-${TIME}-${DATE}-${VERSION_NUMBER}.zip"
fi

if [ "$ENABLE_DEBUG" = "1" ]; then
  echo -e "\n🐞 \033[1;33mENABLE_DEBUG=1: aktifkan pstore + panic-on-hang...\033[0m"
  $CFG --enable CONFIG_PSTORE
  $CFG --enable CONFIG_PSTORE_CONSOLE
  $CFG --enable CONFIG_PSTORE_PMSG
  $CFG --enable CONFIG_PSTORE_RAM
  $CFG --enable CONFIG_PANIC_ON_OOPS
  $CFG --enable CONFIG_DETECT_HUNG_TASK
  $CFG --enable CONFIG_BOOTPARAM_HUNG_TASK_PANIC
  $CFG --enable CONFIG_BOOTPARAM_SOFTLOCKUP_PANIC
  $CFG --enable CONFIG_DEBUG_LIST
  BUILD_TYPE="${BUILD_TYPE}-DEBUG"
  ZIPNAME="${KERNEL_NAME}-${VARIANT}-${DEVICE}-${BUILD_TYPE}-${TIME}-${DATE}-${VERSION_NUMBER}.zip"
fi

if [ "$ENABLE_KSU" = "1" ]; then
  echo -e "\n🔥 \033[1;35mEnabling BakaSU...\033[0m"


  $CFG --enable CONFIG_KSU
  $CFG --enable CONFIG_KSU_MANUAL_HOOK
  $CFG --disable CONFIG_KSU_KPROBES_HOOK

  if [ "$ENABLE_SUSFS" = "1" ]; then
    echo -e "🛡️  \033[1;35mEnabling SUSFS...\033[0m"
    $CFG --enable CONFIG_KSU_SUSFS
    $CFG --enable CONFIG_KSU_SUSFS_SUS_PATH
    $CFG --enable CONFIG_KSU_SUSFS_SUS_MOUNT
    $CFG --enable CONFIG_KSU_SUSFS_SUS_KSTAT
    $CFG --enable CONFIG_KSU_SUSFS_TRY_UMOUNT
    $CFG --enable CONFIG_KSU_SUSFS_SPOOF_UNAME
    $CFG --enable CONFIG_KSU_SUSFS_ENABLE_LOG
    $CFG --enable CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS
    $CFG --enable CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
    $CFG --enable CONFIG_KSU_SUSFS_OPEN_REDIRECT
    $CFG --enable CONFIG_KSU_SUSFS_SUS_MAP
    $CFG --disable CONFIG_KSU_SUSFS_SUS_MEMFD
  fi

  make O="$OUT_DIR" ARCH=arm64 LLVM=1 LLVM_IAS=1 olddefconfig

  echo -e "\n🔍 \033[1;36mVerifying configs...\033[0m"

  grep -q "CONFIG_KSU=y" "$OUT_DIR/.config" \
    || die "CONFIG_KSU not enabled! (cek Kconfig BakaSU / symlink drivers/kernelsu)"
  echo -e "✅ CONFIG_KSU=y"

  grep -q "CONFIG_KSU_MANUAL_HOOK=y" "$OUT_DIR/.config" \
    || die "CONFIG_KSU_MANUAL_HOOK not enabled!"
  echo -e "✅ CONFIG_KSU_MANUAL_HOOK=y"

  if [ "$ENABLE_SUSFS" = "1" ]; then
    if grep -q "CONFIG_KSU_SUSFS=y" "$OUT_DIR/.config"; then
      echo -e "✅ CONFIG_KSU_SUSFS=y"
    else
      echo -e "⚠️  CONFIG_KSU_SUSFS not enabled (patch SUSFS 4.14 mungkin belum terpasang)"
    fi
  fi

  # Peringatan: manual hook harus sudah dipatch di source kernel
  if ! grep -q "ksu_handle" fs/exec.c 2>/dev/null; then
    echo -e "⚠️  \033[1;33mHook KSU tidak ditemukan di fs/exec.c. Manual hook belum dipatch?\033[0m"
  fi
else
  echo -e "\n🚫 \033[1;33mMematikan KSU/SUSFS (build kontrol)...\033[0m"
  $CFG --disable CONFIG_KSU
  $CFG --disable CONFIG_KSU_SUSFS
  make O="$OUT_DIR" ARCH=arm64 LLVM=1 LLVM_IAS=1 olddefconfig
fi

echo -e "\n📋 \033[1;36mConfig terkait (KSU / SUSFS / KPROBES / PSTORE):\033[0m"
grep -E "^(# )?CONFIG_(KSU|KPROBES|HAVE_KPROBES|PSTORE|PANIC_ON_OOPS|BOOTPARAM|DETECT_HUNG|KALLSYMS|STRICT_KERNEL_RWX|STRICT_MODULE_RWX|DEBUG_RODATA|RODATA|SECURITY_WRITABLE_HOOKS|CFI|SHADOW_CALL_STACK|SECURITY_SELINUX_DEVELOP)" "$OUT_DIR/.config" || true

# ============================================================
# Compile
# ============================================================
echo -e "\n🚀 \033[1;35mStarting compilation...\033[0m"
make -j"$JOBS" O="$OUT_DIR" \
  ARCH=arm64 \
  LLVM=1 \
  LLVM_IAS=1 \
  CC="$CC_CMD" \
  LD=ld.lld \
  AR=llvm-ar \
  NM=llvm-nm \
  OBJCOPY=llvm-objcopy \
  OBJDUMP=llvm-objdump \
  STRIP=llvm-strip \
  CLANG_TRIPLE="$CLANG_TRIPLE" \
  CROSS_COMPILE="$CROSS_COMPILE" \
  2>&1 | tee "$OUT_DIR/build.log" | grep --line-buffered -E \
  "warning:|error:|fatal:|Killed|No space left|Segmentation fault|clang:.*(unable|crash)|make(\[[0-9]+\])?: \*\*\*" | sed \
  -e 's/warning:/\x1b[1;33mwarning:\x1b[0m/g' \
  -e 's/error:/\x1b[1;31merror:\x1b[0m/g'

BUILD_STATUS=${PIPESTATUS[0]}
if [ "$BUILD_STATUS" -ne 0 ]; then
  show_first_failure_context
  echo -e "\n❌ \033[1;31mKernel compilation failed (see $OUT_DIR/build.log).\033[0m"
  exit "$BUILD_STATUS"
fi

# ============================================================
# Cek image
# ============================================================
KERNEL_IMG="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"
[ -f "$KERNEL_IMG" ] || die "Build failed: Image.gz-dtb not found!"

echo -e "\n✅ \033[1;32mKernel image compiled successfully.\033[0m"

# ============================================================
# Packaging
# ============================================================
echo -e "\n📦 \033[1;34mPacking kernel into flashable zip...\033[0m"
cp "$KERNEL_IMG" "$ANYKERNEL_DIR/zImage"

cd "$ANYKERNEL_DIR" || exit 1
if zip -r9 "$ZIPNAME" ./* -x "*.zip" "*.git*" README.md > /dev/null; then
  echo -e "\n🎉 \033[1;32mFlashable zip created: $ANYKERNEL_DIR/$ZIPNAME\033[0m"
else
  die "Failed to create zip."
fi
