#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/meshcore-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/meshcore-swift-cache"
swift test --disable-sandbox --scratch-path "${TMPDIR:-/tmp}/meshcore-servicer-tests"
