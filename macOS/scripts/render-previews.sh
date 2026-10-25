#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
preview_build="${TMPDIR:-/tmp}/meshcore-preview-build"
mkdir -p "$preview_build"
export CLANG_MODULE_CACHE_PATH="$preview_build/cache"
swiftc -swift-version 5 -parse-as-library -emit-module -emit-library -module-name MeshCoreKit Sources/MeshCoreKit/*.swift -o "$preview_build/libMeshCoreKit.dylib" -emit-module-path "$preview_build/MeshCoreKit.swiftmodule"
preview_sources=()
for source in Sources/MeshCoreServicer/*.swift; do
    if [[ "$source" != */MeshCoreServicerApp.swift ]]; then preview_sources+=("$source"); fi
done
swiftc -swift-version 5 -parse-as-library -I "$preview_build" -L "$preview_build" -lMeshCoreKit -Xlinker -rpath -Xlinker "$preview_build" "${preview_sources[@]}" scripts/render-previews.swift -o "$preview_build/render-previews"
"$preview_build/render-previews" "${1:-/private/tmp/meshcore-ui-previews}"
