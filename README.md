# 内核驱动开发工具包 (Kernel Driver Development Kit)

该工具包是为了快速开发内核模块而制作，**不一定**能保证内核模块能够完全和对应版本的内核兼容。

如果需要保持完美兼容性，需要下载全量内核代码自行编译构建，具体方法不再赘述。

如果不想下载 Clang 的话，使用 NDK Clang 也能编译通过，但是**可能**编译产物的结构体偏移会有所不同。

## 工具包使用办法

clone 后执行

```sh
./setup.sh
```

编译完成之后，创建模块构建即可（参考 module_template）

### 简单校验编译正确性

```sh
cat kdir/android12-5.10/Module.symvers | grep module_layout
cat kdir/android13-5.15/Module.symvers | grep module_layout
cat kdir/android14-6.1/Module.symvers | grep module_layout
```

对比：

```
0x7c24b32d      module_layout   vmlinux EXPORT_SYMBOL
0x0222dd63      module_layout   vmlinux EXPORT_SYMBOL
0xea759d7f      module_layout   vmlinux EXPORT_SYMBOL
```

### 模块构建环境初始化脚本：

```sh
export DDK_ROOT=/opt/ddk

# android12-5.10
export KERNEL_SRC=$DDK_ROOT/kdir/android12-5.10
export CLANG_PATH=$DDK_ROOT/clang/clang-r416183b/bin

# android13-5.15
# export KERNEL_SRC=$DDK_ROOT/kdir/android13-5.15
# export CLANG_PATH=$DDK_ROOT/clang/clang-r450784e/bin

# android14-6.1
# export KERNEL_SRC=$DDK_ROOT/kdir/android14-6.1
# export CLANG_PATH=$DDK_ROOT/clang/clang-r487747c/bin

export PATH=$CLANG_PATH:$PATH
export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64
export LLVM=1
export LLVM_IAS=1
```

### 内核模块Makefile样例

```Makefile
MODULE_NAME := Shami
$(MODULE_NAME)-objs := core.o
obj-m := $(MODULE_NAME).o

ccflags-y += -Wno-declaration-after-statement
ccflags-y += -Wno-unused-variable
ccflags-y += -Wno-int-conversion
ccflags-y += -Wno-unused-result
ccflags-y += -Wno-unused-function
ccflags-y += -Wno-builtin-macro-redefined -U__FILE__ -D__FILE__='""'

KDIR := $(KERNEL_SRC)
MDIR := $(realpath $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

$(info -- KDIR: $(KDIR))
$(info -- MDIR: $(MDIR))

all:
	make -C $(KDIR) M=$(MDIR) modules
compdb:
	python3 $(MDIR)/.vscode/generate_compdb.py -O $(KDIR) $(MDIR)
clean:
	make -C $(KDIR) M=$(MDIR) clean
```

### 配置代码提示

vscode 安装 clangd 插件

执行：

```sh
python3 .vscode/generate_compdb.py -O $DDK_ROOT/kdir/android14-6.1 .
```

或者直接：

```sh
make compdb
```
