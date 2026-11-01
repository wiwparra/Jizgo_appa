#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Darwin ] || ! command -v xcodebuild >/dev/null 2>&1; then
    echo 'Se requiere un Mac con Xcode completo y los SDK iOS/macOS. No se han compilado los destinos Apple.' >&2
    exit 1
fi
./Scripts/test.sh
xcodebuild -project HogarFinanzas.xcodeproj -scheme HogarFinanzas -destination 'generic/platform=macOS' -derivedDataPath .build/apple-mac CODE_SIGNING_ALLOWED=NO build
xcodebuild -project HogarFinanzas.xcodeproj -scheme HogarFinanzas -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/apple-ios CODE_SIGNING_ALLOWED=NO build
