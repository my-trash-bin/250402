#!/bin/sh

set -e

cd "$(dirname "$0")"


zig build && zig-out/bin/app.exe
