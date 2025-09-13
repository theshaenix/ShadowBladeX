#!/bin/bash

# Kernel build configuration
KERNEL_NAME="ShadowBladeX"
DEVICE="reatoll"
VARIANT="perf"
BUILD_TYPE="nonKSU"
VERSION_NUMBER="v1.0.2"

DATE=$(date +%Y%m%d)
BASE_ZIPNAME="${KERNEL_NAME}-${VARIANT}-${DEVICE}-${BUILD_TYPE}-${DATE}-${VERSION_NUMBER}"
ZIPNAME="${BASE_ZIPNAME}.zip"

# Paths
export KERNEL_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export CLANG_PATH=~/tools/proton-clang
export GCC_PATH=~/tools/gcc-aarch64-linux-gnu-9.3
export ANYKERNEL_DIR=~/tools/AnyKernel3
export OUT_DIR=out

export PATH=$CLANG_PATH/bin:$GCC_PATH/bin:$PATH
export ARCH=arm64
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-

# =====================[ START PROCESS ]=====================

echo -e "\n🛠️  \033[1;34mStarting Kernel Build: $BASE_ZIPNAME\033[0m"


echo -e "\n🔧 \033[1;36mCompiler Info:\033[0m"
clang --version | head -n 1
aarch64-linux-gcc --version | head -n 1

echo -e "\n📱 \033[1;32mTarget Device: $DEVICE\033[0m"

# =====================[ DEFCONFIG ]=====================

echo -e "\n📄 \033[1;36mSetting up defconfig...\033[0m"
make O=$OUT_DIR ARCH=arm64 atoll_defconfig

if [ $? -ne 0 ]; then
  echo -e "\n❌ \033[1;31mDefconfig failed. Exiting.\033[0m"
  exit 1
fi

# =====================[ COMPILING ]=====================

echo -e "\n🚀 \033[1;35mStarting compilation...\033[0m"
make -j$(nproc) O=$OUT_DIR \
  ARCH=arm64 \
  CC=clang \
  LD=ld.lld \
  AR=llvm-ar \
  NM=llvm-nm \
  OBJCOPY=llvm-objcopy \
  OBJDUMP=llvm-objdump \
  STRIP=llvm-strip \
  CLANG_TRIPLE=$CLANG_TRIPLE \
  CROSS_COMPILE=$CROSS_COMPILE \
  2>&1 | tee out/build.log | grep --line-buffered -E "warning:|error:" | sed \
  -e 's/warning:/\x1b[1;33mwarning:\x1b[0m/g' \
  -e 's/error:/\x1b[1;31merror:\x1b[0m/g'

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
