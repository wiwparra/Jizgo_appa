#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ -x /workspace/toolchains/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin/swift ]; then
    PATH="/workspace/toolchains/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin:$PATH"
    export PATH
fi
if [ "$(uname -s)" = Linux ]; then
    export XDG_CACHE_HOME=/workspace/swift-cache
    export CLANG_MODULE_CACHE_PATH=/workspace/swift-cache/clang
    export SWIFTPM_MODULECACHE_OVERRIDE=/workspace/swift-cache/modules
    exec swift test --cache-path /workspace/swift-cache/pm --config-path /workspace/swift-cache/config --security-path /workspace/swift-cache/security -j 4 "$@"
fi
exec swift test "$@"
