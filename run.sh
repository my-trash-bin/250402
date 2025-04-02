#!/bin/sh

set -e

cd "$(dirname "$0")"


zig build

cmake -DCMAKE_BUILD_TYPE=Release -B builddirs/dummy dummy
cmake --build builddirs/dummy --config Debug
