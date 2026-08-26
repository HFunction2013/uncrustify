#!/bin/bash
# ============================================================================
# Uncrustify WASM 完整编译脚本
# 编译 HFunction2013/uncrustify 为 WebAssembly，支持浏览器和 Node.js
# ============================================================================
#
# 用法:
#   1. 安装 Emscripten SDK:
#      git clone https://github.com/emscripten-core/emsdk.git
#      cd emsdk
#      ./emsdk install 3.1.60
#      ./emsdk activate 3.1.60
#      source ./emsdk_env.sh
#
#   2. 克隆 uncrustify 仓库:
#      git clone https://github.com/HFunction2013/uncrustify.git
#      cd uncrustify
#
#   3. 运行本脚本:
#      bash build_wasm.sh
#
# 产物:
#   dist/libUncrustify.js  - JS 胶水代码
#   dist/libUncrustify.wasm - WebAssembly 二进制
# ============================================================================
set -e
# 检查 emcc 是否可用
if ! command -v emcc &> /dev/null; then
    echo "错误: 未找到 emcc，请先安装并激活 Emscripten SDK"
    echo "  source /path/to/emsdk/emsdk_env.sh"
    exit 1
fi
echo "=== Uncrustify WASM 编译 ==="
echo "Emscripten: $(emcc --version | head -1)"
echo ""
# 项目根目录（脚本放在 uncrustify 根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
BUILD_DIR="$PROJECT_DIR/build-wasm-manual"
DIST_DIR="$PROJECT_DIR/dist"
echo "项目目录: $PROJECT_DIR"
echo "构建目录: $BUILD_DIR"
echo ""
# 完全清理旧构建，杜绝缓存残留
rm -rf "$BUILD_DIR"
rm -rf "$DIST_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$DIST_DIR"
# ----------------------------------------------------------------------------
# 步骤 1: 生成必要的头文件（全部调用仓库官方脚本，禁止手写占位）
# ----------------------------------------------------------------------------
echo "[1/5] 生成头文件..."
# config.h - 强制定义所有标准头文件（Emscripten 环境下 CMake 检测会失败）
cat > "$BUILD_DIR/config.h" << 'EOF'
#define HAVE_INTTYPES_H 1
#define HAVE_MEMORY_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRINGS_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1
#define HAVE_UTIME_H 1
#define HAVE_STDBOOL_H 1
#define HAVE_MEMSET 1
#define HAVE_STRCASECMP 1
#define HAVE_STRCHR 1
#define HAVE_STRDUP 1
#define HAVE_STRERROR 1
#define HAVE_STRTOL 1
#define HAVE_STRTOUL 1
#define HAVE__BOOL 1
#define STDC_HEADERS 1
#define PACKAGE "uncrustify"
#define PACKAGE_NAME "uncrustify"
#define PACKAGE_VERSION "0.83.0"
#define PACKAGE_STRING "uncrustify 0.83.0"
#define PACKAGE_BUGREPORT ""
#define PACKAGE_TARNAME "uncrustify"
#define PACKAGE_URL ""
#define VERSION "0.83.0"
EOF

# uncrustify_version.h
cat > "$BUILD_DIR/uncrustify_version.h" << 'EOF'
#define UNCRUSTIFY_VERSION "Uncrustify-0.83.0-mod"
EOF

# token_names.h 【修复：调用仓库官方脚本，禁止手写占位】
echo "  generate token_names.h"
if [ ! -f "$PROJECT_DIR/scripts/make_token_names.py" ]; then
    echo "FATAL: missing scripts/make_token_names.py"
    exit 1
fi
python3 "$PROJECT_DIR/scripts/make_token_names.py" "$PROJECT_DIR/src/token_enum.h" "$BUILD_DIR/token_names.h"

# options.cpp / option_enum
mkdir -p "$BUILD_DIR/src"
if [ ! -f "$PROJECT_DIR/scripts/make_options.py" ]; then echo "FATAL missing make_options.py"; exit 1; fi
python3 "$PROJECT_DIR/scripts/make_options.py" "$BUILD_DIR/src/options.cpp" "$PROJECT_DIR/src/options.h" "$PROJECT_DIR/src/options.cpp.in"

if [ ! -f "$PROJECT_DIR/scripts/make_option_enum.py" ]; then echo "FATAL missing make_option_enum.py"; exit 1; fi
python3 "$PROJECT_DIR/scripts/make_option_enum.py" "$BUILD_DIR/src/option_enum.h" "$PROJECT_DIR/src/option.h" "$PROJECT_DIR/src/option_enum.h.in"
python3 "$PROJECT_DIR/scripts/make_option_enum.py" "$BUILD_DIR/src/option_enum.cpp" "$PROJECT_DIR/src/option.h" "$PROJECT_DIR/src/option_enum.cpp.in"

if [ ! -f "$PROJECT_DIR/scripts/make_punctuator_table.py" ]; then echo "FATAL missing make_punctuator_table.py"; exit 1; fi
python3 "$PROJECT_DIR/scripts/make_punctuator_table.py" "$BUILD_DIR/src/punctuator_table.h" "$PROJECT_DIR/src/symbols_table.h"

echo "  头文件生成完成"
# ----------------------------------------------------------------------------
# 步骤 2: 收集所有源文件（包括子目录！）
# ----------------------------------------------------------------------------
echo "[2/5] 收集源文件..."
SRC_FILES=""
SRC_FILES="$SRC_FILES $(find $PROJECT_DIR/src -maxdepth 1 -name '*.cpp' ! -name 'uncrustify_emscripten.cpp')"
SRC_FILES="$SRC_FILES $(find $PROJECT_DIR/src/align -name '*.cpp')"
SRC_FILES="$SRC_FILES $(find $PROJECT_DIR/src/newlines -name '*.cpp')"
SRC_FILES="$SRC_FILES $(find $PROJECT_DIR/src/tokenizer -name '*.cpp')"
# 生成的源文件
SRC_FILES="$SRC_FILES $BUILD_DIR/src/options.cpp"
SRC_FILES="$SRC_FILES $BUILD_DIR/src/option_enum.cpp"
SRC_COUNT=$(echo $SRC_FILES | wc -w)
echo "  共 $SRC_COUNT 个源文件"
echo "  根目录: $(find $PROJECT_DIR/src -maxdepth 1 -name '*.cpp' ! -name 'uncrustify_emscripten.cpp' | wc -l)"
echo "  align/: $(find $PROJECT_DIR/src/align -name '*.cpp' | wc -l)"
echo "  newlines/: $(find $PROJECT_DIR/src/newlines -name '*.cpp' | wc -l)"
echo "  tokenizer/: $(find $PROJECT_DIR/src/tokenizer -name '*.cpp' | wc -l)"
# ----------------------------------------------------------------------------
# 步骤 3: 编译所有源文件为 .o
# ----------------------------------------------------------------------------
echo "[3/5] 编译源文件..."
OBJ_DIR="$BUILD_DIR/obj"
mkdir -p "$OBJ_DIR"
INCLUDES="-I$BUILD_DIR -I$BUILD_DIR/src -I$PROJECT_DIR/src -I$PROJECT_DIR/src/align -I$PROJECT_DIR/src/newlines -I$PROJECT_DIR/src/tokenizer"
CFLAGS="-O3 -DNDEBUG -DEMSCRIPTEN $INCLUDES"
OBJ_FILES=""
INDEX=0
TOTAL=$SRC_COUNT
for src in $SRC_FILES; do
    INDEX=$((INDEX + 1))
    rel_path="${src#$PROJECT_DIR/}"
    obj_name=$(echo "$rel_path" | tr '/' '_' | sed 's/\.cpp$/.o/')
    obj="$OBJ_DIR/$obj_name"
    echo "  [$INDEX/$TOTAL] $(basename $src)"
    emcc -c $CFLAGS "$src" -o "$obj"
    OBJ_FILES="$OBJ_FILES $obj"
done
echo "  编译完成，共 $(echo $OBJ_FILES | wc -w) 个目标文件"
# ----------------------------------------------------------------------------
# 步骤 4: 链接为 WebAssembly
# ----------------------------------------------------------------------------
echo "[4/5] 链接为 WebAssembly..."
em++ -O3 -DNDEBUG \
    -s INITIAL_MEMORY=67108864 \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s MODULARIZE=1 \
    -s EXPORT_NAME="'libUncrustify'" \
    -s ERROR_ON_UNDEFINED_SYMBOLS=1 \
    -s FORCE_FILESYSTEM=1 \
    -s EXIT_RUNTIME=0 \
    -s EXPORTED_RUNTIME_METHODS=["UTF8ToString","stringToUTF8","lengthBytesUTF8","writeAsciiToMemory","ccall","cwrap","callMain","FS","getValue","setValue"] \
    -s EXPORTED_FUNCTIONS=["_main","_malloc","_free"] \
    -s WASM=1 \
    -s ENVIRONMENT=web,node \
    $OBJ_FILES \
    -o "$DIST_DIR/libUncrustify.js"
sed -i 's/libUncrustify\.wasm/libUncrustify.wasm/g' "$DIST_DIR/libUncrustify.js"
echo "  链接完成"
# ----------------------------------------------------------------------------
# 步骤 5: 验证产物
# ----------------------------------------------------------------------------
echo "[5/5] 验证产物..."
ls -lh "$DIST_DIR/"
WASM_MAGIC=$(head -c4 "$DIST_DIR/libUncrustify.wasm" | xxd -p)
if [ "$WASM_MAGIC" = "0061736d" ]; then
    echo "  ✓ WASM 文件有效 (magic: 0x$WASM_MAGIC)"
else
    echo "  ✗ WASM 文件无效 (magic: 0x$WASM_MAGIC)"
    exit 1
fi
echo ""
echo "=== 编译成功 ==="
echo "产物位置: $DIST_DIR/"
echo "  - libUncrustify.js"
echo "  - libUncrustify.wasm"
echo ""