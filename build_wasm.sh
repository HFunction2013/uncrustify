#!/bin/bash
set -e
if ! command -v emcc &> /dev/null; then
  echo "Please source emsdk_env.sh first"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/emscripten"

rm -rf build
mkdir build
cd build

cmake .. -DCMAKE_TOOLCHAIN_FILE=${EMSDK}/upstream/emscripten/cmake/Modules/Emscripten.cmake

make -j$(nproc)

# 拷贝产物到根目录dist
mkdir -p ${SCRIPT_DIR}/dist
cp libUncrustify.js ${SCRIPT_DIR}/dist/
cp libUncrustify.wasm ${SCRIPT_DIR}/dist/

# 校验wasm魔数
WASM_MAGIC=$(head -c4 ${SCRIPT_DIR}/dist/libUncrustify.wasm | xxd -p)
if [ "$WASM_MAGIC" != "0061736d" ]; then
  echo "ERROR: invalid wasm binary"
  exit 1
fi

echo "✅ build done, output: ./dist"