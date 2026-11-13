#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/eevee-native-config.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun clang -fobjc-arc -fblocks -std=gnu11 -Wall -Wextra -Werror \
    -framework Foundation -ISources/EeveeSpotifyC/include \
    Sources/EeveeSpotifyC/NativeConfigDiagnostics.m \
    Tests/NativeConfigurationDiagnostics/main.m \
    -o "$TEST_DIR/native-config-tests"
"$TEST_DIR/native-config-tests"
"$TEST_DIR/native-config-tests" mismatch
xcrun swiftc -typecheck \
    -import-objc-header Sources/EeveeSpotifyC/include/NativeConfigDiagnostics.h \
    Tests/NativeConfigurationDiagnostics/bridge.swift

xcrun clang -fobjc-arc -fblocks -std=gnu11 -Wall -Wextra -Werror \
    -framework Foundation -ISources/EeveeSpotifyC/include \
    Sources/EeveeSpotifyC/ProductStateDiagnostics.m \
    Tests/ProductStateDiagnostics/main.m \
    -o "$TEST_DIR/product-state-tests"
"$TEST_DIR/product-state-tests"
"$TEST_DIR/product-state-tests" mismatch
"$TEST_DIR/product-state-tests" inherited
xcrun swiftc -typecheck \
    -import-objc-header Sources/EeveeSpotifyC/include/ProductStateDiagnostics.h \
    Tests/ProductStateDiagnostics/bridge.swift

xcrun clang -fobjc-arc -fblocks -std=gnu11 -Wall -Wextra -Werror \
    -framework Foundation -ISources/EeveeSpotifyC/include \
    Sources/EeveeSpotifyC/PlaybackDiagnostics.m \
    Tests/PlaybackDiagnostics/main.m \
    -o "$TEST_DIR/playback-diagnostics-tests"
"$TEST_DIR/playback-diagnostics-tests"
"$TEST_DIR/playback-diagnostics-tests" mismatch
"$TEST_DIR/playback-diagnostics-tests" inherited
xcrun swiftc -typecheck \
    -import-objc-header Sources/EeveeSpotifyC/include/PlaybackDiagnostics.h \
    Tests/PlaybackDiagnostics/bridge.swift
