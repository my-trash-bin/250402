#!/bin/sh

cd "$(dirname "$0")"



# git submodule

git submodule update --init



# glfw

cmake -DCMAKE_BUILD_TYPE=Debug -DCMAKE_INSTALL_PREFIX=deps/glfw-debug -B builddirs/glfw-debug submodules/glfw
cmake --build builddirs/glfw-debug --config Debug
cmake --install builddirs/glfw-debug --config Debug
cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=deps/glfw-release -B builddirs/glfw-release submodules/glfw
cmake --build builddirs/glfw-release --config Release
cmake --install builddirs/glfw-release --config Release



# compile_commands.json

set -e

if command -v cmd > /dev/null; then
    PWD="$(cmd //c cd | sed 's|\\|\\\\\\\\|g' | sed s/\"/\\\"/g)"
else
    PWD="$(pwd | sed 's|\\|\\\\\\\\|g' | sed s/\"/\\\"/g)"
fi

echo '[
  {
    "directory": "[[WORKSPACE]]",
    "file": "src/lib.c",
    "output": "/dev/null",
    "arguments": [
      "clang",
      "-xc",
      "src/lib.c",
      "-o",
      "/dev/null",
      "-I",
      "submodules/glfw/include",
      "-I",
      "submodules/glfw/deps",
      "-std=c99",
      "-c"
    ]
  }
]
' | sed "s\\[\\[WORKSPACE\\]\\]$PWDg" > compile_commands.json
