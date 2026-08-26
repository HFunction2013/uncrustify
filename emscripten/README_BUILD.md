# Uncrustify WASM 编译说明

## 概述

本目录包含将 [HFunction2013/uncrustify](https://github.com/HFunction2013/uncrustify) 编译为 WebAssembly 所需的修改后的源码和编译脚本。

## 目录结构

```
uncrustify-wasm-src/
├── README_BUILD.md          # 本文件
├── build_wasm.sh            # 一键编译脚本（推荐）
├── emscripten/
│   └── CMakeLists.txt       # 修改后的 Emscripten CMake 配置
└── src/
    └── uncrustify_emscripten.cpp  # 修改后的 Emscripten 接口文件
```

## 修改内容

### 1. `emscripten/CMakeLists.txt`

主要修改：
- `-s WASM=0` → `-s WASM=1`：启用 WebAssembly（原配置是 asm.js）
- 添加 `-s ENVIRONMENT=web,node`：同时支持浏览器和 Node.js
- `EXTRA_EXPORTED_RUNTIME_METHODS` → `EXPORTED_RUNTIME_METHODS`：适配新版 Emscripten
- 添加 `-s FORCE_FILESYSTEM=1`：强制包含虚拟文件系统
- 添加 `-s EXIT_RUNTIME=0`：防止运行时退出
- 导出 `callMain`、`FS`、`ccall`、`cwrap` 等运行时方法
- 强制设置所有 `HAVE_*` 宏（Emscripten 环境下 CMake 头文件检测会失败）
- 禁用 POST_BUILD 的 catFiles 步骤（会破坏现代 Emscripten 输出）

### 2. `src/uncrustify_emscripten.cpp`

主要修改：
- `#if defined (__linux__)` → `#if defined (__linux__) || defined (EMSCRIPTEN)`
- 原代码在 Emscripten 环境下因 `__linux__` 未定义而被排除，导致目标文件只有 333 字节（空文件），进而导致 wasm-ld 生成全零的无效 wasm 文件

## 重要：编译所有子目录源文件

**原 CMake 配置的重大缺陷**：只编译了 `src/*.cpp`，漏掉了三个子目录：
- `src/align/`（25个文件）- 代码对齐功能
- `src/newlines/`（44个文件）- 换行处理功能
- `src/tokenizer/`（19个文件）- 词法分析（包含核心 `tokenize` 函数）

**共漏掉 88 个源文件**，导致运行时缺少 `tokenize`、`align_all`、`newlines_functions_remove_extra_blank_lines` 等核心函数。

`build_wasm.sh` 脚本已正确包含所有子目录的源文件。

## 编译方法

### 方法一：使用一键编译脚本（推荐）

```bash
# 1. 安装 Emscripten SDK
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
./emsdk install latest
./emsdk activate latest
source ./emsdk_env.sh

# 2. 克隆 uncrustify 仓库
cd ..
git clone https://github.com/HFunction2013/uncrustify.git
cd uncrustify

# 3. 应用修改（替换文件）
cp /path/to/uncrustify-wasm-src/emscripten/CMakeLists.txt emscripten/
cp /path/to/uncrustify-wasm-src/src/uncrustify_emscripten.cpp src/
cp /path/to/uncrustify-wasm-src/build_wasm.sh .

# 4. 运行编译脚本
bash build_wasm.sh
```

产物在 `dist/` 目录：
- `dist/libUncrustify.js` - JS 胶水代码
- `dist/libUncrustify.wasm` - WebAssembly 二进制

### 方法二：使用 CMake

```bash
# 注意：原 CMakeLists.txt 有缺陷（漏掉子目录），需要手动修改
# 建议使用 build_wasm.sh 脚本

mkdir build-wasm
cd build-wasm
emcmake cmake ../emscripten
emmake make
```

**注意**：使用 CMake 时需要手动修改 `emscripten/CMakeLists.txt` 中的 `FILE(GLOB unc_infiles ...)` 来包含子目录，否则会缺少核心函数。

## Emscripten 环境注意事项

如果遇到以下问题，可能需要修补 Emscripten 工具链：

### 1. 文件锁权限问题

错误：`PermissionError: [Errno 1] Operation not permitted: ... .lock`

解决：修改 `emsdk/upstream/emscripten/tools/filelock.py`，在 `os.unlink` 外包 try-except。

### 2. strip_sections 生成无效 wasm

错误：`InvalidWasmError: ... is not a valid wasm file`

解决：修改 `emsdk/upstream/emscripten/tools/building.py` 中的 `strip_sections` 函数，在 `check_call` 失败时回退到复制原文件。

### 3. CMake 头文件检测失败

现象：`config.h` 中所有 `HAVE_*` 宏未定义

解决：在 `configure_file` 之前强制设置所有 `HAVE_*` 宏（已在修改后的 CMakeLists.txt 中处理）。

## 验证编译结果

```bash
# Node.js 测试
node -e "
const m = require('./dist/libUncrustify.js');
const fs = require('fs');
m({
  wasmBinary: fs.readFileSync('./dist/libUncrustify.wasm'),
  noInitialRun: true,
  noExitRuntime: true
}).then(mod => {
  mod.FS.writeFile('/tmp/in.c', 'int main(){return 0;}');
  mod.callMain(['-c', '-', '-l', 'C', '-f', '/tmp/in.c', '-o', '/tmp/out.c']);
  console.log(mod.FS.readFile('/tmp/out.c', 'utf8'));
});
"
```

预期输出：
```c
int main(){
	return 0;
}
```

## 编译参数说明

| 参数 | 说明 |
|------|------|
| `-s WASM=1` | 生成 WebAssembly（非 asm.js） |
| `-s MODULARIZE=1` | 模块化导出，返回工厂函数 |
| `-s EXPORT_NAME='libUncrustify'` | 导出的模块名 |
| `-s ENVIRONMENT=web,node` | 同时支持浏览器和 Node.js |
| `-s FORCE_FILESYSTEM=1` | 强制包含虚拟文件系统（用于读写输入输出文件） |
| `-s EXIT_RUNTIME=0` | 防止 main 函数退出后终止运行时 |
| `-s ALLOW_MEMORY_GROWTH=1` | 允许动态增长内存 |
| `-s INITIAL_MEMORY=67108864` | 初始内存 64MB |
| `-s ERROR_ON_UNDEFINED_SYMBOLS=0` | 未定义符号只警告不报错 |
| `-O3` | 最高优化级别 |

## 许可证

GPL-2.0-or-later（与 uncrustify 相同）
