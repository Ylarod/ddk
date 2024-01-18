export DDK_ROOT=/home/ylarod/KernelCompile/ddk

# android12-5.10
# export KERNEL_SRC=$DDK_ROOT/kdir/android12-5.10
# export CLANG_PATH=$DDK_ROOT/clang/clang-r416183b/bin

# android13-5.15
# export KERNEL_SRC=$DDK_ROOT/kdir/android13-5.15
# export CLANG_PATH=$DDK_ROOT/clang/clang-r450784e/bin

# android14-6.1
export KERNEL_SRC=$DDK_ROOT/kdir/android14-6.1
export CLANG_PATH=$DDK_ROOT/clang/clang-r487747c/bin

export PATH=$CLANG_PATH:$PATH
export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64
export LLVM=1
export LLVM_IAS=1