#!/bin/sh

set -e

cd "$(dirname "$0")"

zig build run -Doptimize=ReleaseFast
