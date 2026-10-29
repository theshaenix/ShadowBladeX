#!/bin/bash

# ============================================================
# Pre-build checks for required toolchains and AnyKernel3
# ============================================================

# Paths
CLANG_DIR=\~/toolchains/clang
GCC_DIR=\~/toolchains/gcc-aarch64-linux-gnu-9.3
ANYKERNEL_DIR=\~/AnyKernel3

# Check Clang
if [ ! -d "$CLANG_DIR" ]; then
  echo -e "\n🔍 \033[1;33mClang toolchain not found. Cloning...\033[0m"
  git clone --depth=1 --branch lineage-20.0 \
    https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b.git "$CLANG_DIR"
else
  echo -e "\n✅ \033[1;32mClang toolchain already present.\033[0m"
fi

# Check GCC
if [ ! -d "$GCC_DIR" ]; then
  echo -e "\n🔍 \033[1;33mGCC toolchain not found. Cloning...\033[0m"
  git clone --depth=1 --branch lineage-23.0 \
    https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-9.3.git "$GCC_DIR"
else
  echo -e "\n✅ \033[1;32mGCC toolchain already present.\033[0m"
fi

# Check AnyKernel3
if [ ! -d "$ANYKERNEL_DIR" ]; then
  echo -e "\n🔍 \033[1;33mAnyKernel3 not found. Cloning...\033[0m"
  git clone --depth=1 https://github.com/theshaenix/AnyKernel3.git "$ANYKERNEL_DIR"
else
  echo -e "\n✅ \033[1;32mAnyKernel3 folder already present.\033[0m"
fi

# =====================[ UPDATE ANYKERNEL STRING ]=====================
echo -e "\n✏️  \033[1;36mUpdating AnyKernel branding...\033[0m"

KERNEL_STRING="Nezuko BakaSU | RMX2061"
FLASH_MESSAGE="Nezuko BakaSU flashed successfully!"

if [ -f "$ANYKERNEL_DIR/anykernel.sh" ]; then
  sed -i "s|^kernel.string=.*|kernel.string=${KERNEL_STRING}|" "$ANYKERNEL_DIR/anykernel.sh"
  sed -i "s|Ka-chow!.*McQueen is ready to race.|${FLASH_MESSAGE}|" "$ANYKERNEL_DIR/anykernel.sh"
  echo -e "✅ kernel.string  → ${KERNEL_STRING}"
  echo -e "✅ flash message  → ${FLASH_MESSAGE}"
else
  echo -e "⚠️  anykernel.sh not found"
fi

# =====================[ SETUP BAKASU ]=====================
echo -e "\n🔥 Setting up BakaSU..."

rm -rf drivers/kernelsu KernelSU
git clone --depth=1 https://github.com/Baka-SU/BakaSU.git KernelSU
ln -sf ../KernelSU/kernel drivers/kernelsu

if ! grep -q "kernelsu" drivers/Makefile; then
  echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile
fi

if ! grep -q "kernelsu" drivers/Kconfig; then
  sed -i '/endmenu/i\source "drivers/kernelsu/Kconfig"' drivers/Kconfig
fi

echo -e "✅ BakaSU ready"

# ============================================================
# Build configuration
# ============================================================

KERNEL_NAME="Nezuko-"
DEVICE="RMX2061"
VARIANT="perf"
BUILD_TYPE="BakaSU"
VERSION_NUMBER="v1"

DATE=$(date +%Y%m%d)
TIME=$(date +%H%M)
BASE_ZIPNAME="\( {KERNEL_NAME}- \){VARIANT}-\( {DEVICE}- \){BUILD_TYPE}-\( {TIME}- \){DATE}-${VERSION_NUMBER}"
ZIPNAME="${BASE_ZIPNAME}.zip"

export KERNEL_ROOT="\( ( cd " \)( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export CLANG_PATH=$CLANG_DIR
export GCC_PATH=$GCC_DIR
export ANYKERNEL_DIR=$ANYKERNEL_DIR
export OUT_DIR=out

export PATH=$CLANG_PATH/bin:$GCC_PATH/bin:$PATH
export ARCH=arm64
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-

JOBS="\( {JOBS:- \)(nproc)}"

show_first_failure_context() {
  local failure_line context_start context_end

  failure_line=$(grep -n -m1 -E \
    '(^|: )(fatal )?error:|fatal:|clang:.*(unable|crash)|make(\[[0-9]+\])?: \*\*\*' \
    "$OUT_DIR/build.log" | cut -d: -f1)

  if [ -n "$failure_line" ]; then
    context_start=$((failure_line > 40 ? failure_line - 40 : 1))
    context_end=$((failure_line + 20))
    echo -e "\n🔎 \033[1;36mFirst failure context from $OUT_DIR/build.log:\033[0m"
    sed -n "\( {context_start}, \){context_end}p" "$OUT_DIR/build.log"
  fi
}

# =====================[ START PROCESS ]=====================

echo -e "\n🛠️  \033[1;34mStarting Kernel Build: $BASE_ZIPNAME\033[0m"

echo -e "\n🧹 \033[1;33mCleaning output and ccache...\033[0m"
rm -rf $OUT_DIR/*
rm -f "$ANYKERNEL_DIR/zImage"
ccache -C > /dev/null 2>&1

echo -e "\n🔧 \033[1;36mCompiler Info:\033[0m"
clang --version | head -n 1
aarch64-linux-gcc --version | head -n 1

echo -e "\n📱 \033[1;32mTarget Device: $DEVICE\033[0m"
echo -e "🧵 \033[1;36mParallel build jobs: $JOBS\033[0m"

# =====================[ DEFCONFIG ]=====================

echo -e "\n📄 \033[1;36mSetting up defconfig...\033[0m"
make O=$OUT_DIR ARCH=arm64 LLVM=1 LLVM_IAS=1 atoll_defconfig

if [ $? -ne 0 ]; then
  echo -e "\n❌ \033[1;31mDefconfig failed. Exiting.\033[0m"
  exit 1
fi

# =====================[ ENABLE BAKASU + SUSFS ]=====================
echo -e "\n🔥 \033[1;35mEnabling BakaSU + SUSFS...\033[0m"

./scripts/config --file $OUT_DIR/.config --enable CONFIG_KSU
./scripts/config --file $OUT_DIR/.config --enable CONFIG_KSU_MANUAL_HOOK
./scripts/config --file $OUT_DIR/.config --disable CONFIG_KSU_KPROBES_HOOK

./scripts/config --file $OUT_DIR/.config --enable CONFIG_KSU_SUSFS
./scripts/config --file $OUT_DIR/.config --enable CONFIG_KSU_SUSFS_SUS_PATH
./scripts/config --file $OUT_DIR/.config --enable CONFIG_KSU_SUSFS_SUS_MOUNT
./scripts/config --file $OUT_DIR/.config --enable CONFIG_KSU_SUSFS_SUS_KSTAT
./scripts/config --file $OUT_DIR/.config --enable CONFIG_KSU_SUSFS_TRY_UMOUNT
./scripts/config --file $OUT_DIR/.config --enable CONFIG_KSU_SUSFS_SPOOF_UNAME
./scripts/config --file $OUT_DIR/.config --enable CONFIG_KSU_SUSFS_ENABLE_LOG
./scripts/config --file $OUT_DIR/.config --enable CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS
./scripts/config --file $OUT_DIR/.config --enable CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
./scripts/config --file $OUT_DIR/.config --enable CONFIG_KSU_SUSFS_OPEN_REDIRECT
./scripts/config --file $OUT_DIR/.config --enable CONFIG_KSU_SUSFS_SUS_MAP
./scripts/config --file $OUT_DIR/.config --disable CONFIG_KSU_SUSFS_SUS_MEMFD

make O=$OUT_DIR ARCH=arm64 LLVM=1 LLVM_IAS=1 olddefconfig

echo -e "\n🔍 \033[1;36mVerifying KernelSU configs...\033[0m"
if grep -q "CONFIG_KSU=y" "$OUT_DIR/.config"; then
  echo -e "✅ CONFIG_KSU=y"
else
  echo -e "❌ CONFIG_KSU not enabled!"
  exit 1
fi

if grep -q "CONFIG_KSU_MANUAL_HOOK=y" "$OUT_DIR/.config"; then
  echo -e "✅ CONFIG_KSU_MANUAL_HOOK=y"
else
  echo -e "❌ CONFIG_KSU_MANUAL_HOOK not enabled!"
  exit 1
fi

if grep -q "CONFIG_KSU_SUSFS=y" "$OUT_DIR/.config"; then
  echo -e "✅ CONFIG_KSU_SUSFS=y"
else
  echo -e "⚠️  CONFIG_KSU_SUSFS not enabled (optional)"
fi

# Kernel FCM level 7 requirements
required_configs=(
  CONFIG_AS_IS_LLVM CONFIG_CC_IS_CLANG CONFIG_CFI_CLANG CONFIG_HIDRAW
  CONFIG_HID_PLAYSTATION CONFIG_KFENCE CONFIG_LD_IS_LLD CONFIG_NET_ACT_BPF
  CONFIG_NET_ACT_POLICE CONFIG_NET_CLS_MATCHALL CONFIG_NET_SCH_TBF
  CONFIG_PLAYSTATION_FF CONFIG_RD_LZ4 CONFIG_SHADOW_CALL_STACK
)
for config in "${required_configs[@]}"; do
  if ! grep -qx "$config=y" "$OUT_DIR/.config"; then
    echo -e "\n❌ \033[1;31mRequired kernel config missing: $config\033[0m"
    exit 1
  fi
done

# =====================[ COMPILING ]=====================

echo -e "\n🚀 \033[1;35mStarting compilation...\033[0m"
make -j"$JOBS" O=$OUT_DIR \
  ARCH=arm64 \
  LLVM=1 \
  LLVM_IAS=1 \
  CC=clang \
  LD=ld.lld \
  AR=llvm-ar \
  NM=llvm-nm \
  OBJCOPY=llvm-objcopy \
  OBJDUMP=llvm-objdump \
  STRIP=llvm-strip \
  CLANG_TRIPLE=$CLANG_TRIPLE \
  CROSS_COMPILE=$CROSS_COMPILE \
  2>&1 | tee out/build.log | grep --line-buffered -E \
  "warning:|error:|fatal:|Killed|No space left|Segmentation fault|clang:.*(unable|crash)|make(\[[0-9]+\])?: \*\*\*" | sed \
  -e 's/warning:/\x1b[1;33mwarning:\x1b[0m/g' \
  -e 's/error:/\x1b[1;31merror:\x1b[0m/g'

BUILD_STATUS=${PIPESTATUS[0]}
if [ "$BUILD_STATUS" -ne 0 ]; then
  show_first_failure_context
  echo -e "\n❌ \033[1;31mKernel compilation failed (see $OUT_DIR/build.log).\033[0m"
  exit "$BUILD_STATUS"
fi

# =====================[ CHECK IMAGE ]=====================

KERNEL_IMG=$OUT_DIR/arch/arm64/boot/Image.gz-dtb
if [ ! -f "$KERNEL_IMG" ]; then
  echo -e "\n❌ \033[1;31mBuild failed: Image.gz-dtb not found!\033[0m"
  exit 1
fi

echo -e "\n✅ \033[1;32mKernel image compiled successfully.\033[0m"

# =====================[ PACKAGING ]=====================

echo -e "\n📦 \033[1;34mPacking kernel into flashable zip...\033[0m"
cp "$KERNEL_IMG" "$ANYKERNEL_DIR/zImage"

cd $ANYKERNEL_DIR || exit 1
zip -r9 "$ZIPNAME" * -x "*.zip" "*.git*" README.md > /dev/null

if [ $? -eq 0 ]; then
  echo -e "\n🎉 \033[1;32mFlashable zip created: $ANYKERNEL_DIR/$ZIPNAME\033[0m"
else
  echo -e "\n❌ \033[1;31mFailed to create zip.\033[0m"
  exit 1
fi
