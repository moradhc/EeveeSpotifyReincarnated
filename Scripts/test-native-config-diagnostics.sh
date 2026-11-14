#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/eevee-native-config.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cc -std=c11 -Wall -Wextra -Werror -ISources/EeveeSpotifyC/include \
    Tests/NativePlaybackPolicy/main.c -o "$TEST_DIR/native-playback-policy"
"$TEST_DIR/native-playback-policy"
xcrun --sdk iphoneos clang -target arm64-apple-ios14.0 \
    -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
    -fobjc-arc -fblocks -std=gnu11 -Wall -Wextra -Werror -fsyntax-only \
    -ISources/EeveeSpotifyC/include Sources/EeveeSpotifyC/NativePlaybackFix.m
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
"$TEST_DIR/playback-diagnostics-tests" position-mismatch
xcrun swiftc -typecheck \
    -import-objc-header Sources/EeveeSpotifyC/include/PlaybackDiagnostics.h \
    Tests/PlaybackDiagnostics/bridge.swift

xcrun clang -fobjc-arc -fblocks -std=gnu11 -Wall -Wextra -Werror \
    -framework Foundation -ISources/EeveeSpotifyC/include \
    Sources/EeveeSpotifyC/PlaybackRestrictionPolicy.m \
    Sources/EeveeSpotifyC/PlaybackDiagnostics.m \
    Tests/PlaybackRestrictionPolicy/main.m \
    -o "$TEST_DIR/playback-restriction-policy-tests"
for mode in normal unsupported mismatch inherited with-v7; do
    "$TEST_DIR/playback-restriction-policy-tests" "$mode"
done
xcrun swiftc -typecheck \
    -import-objc-header Sources/EeveeSpotifyC/include/PlaybackRestrictionPolicy.h \
    Tests/PlaybackRestrictionPolicy/bridge.swift

xcrun clang -fobjc-arc -fblocks -std=gnu11 -Wall -Wextra -Werror \
    -framework Foundation -ISources/EeveeSpotifyC/include \
    Sources/EeveeSpotifyC/CommandOutcomeDiagnostics.m \
    Tests/CommandOutcomeDiagnostics/main.m \
    -o "$TEST_DIR/command-outcome-tests"
for mode in normal unsupported mismatch inherited; do
    "$TEST_DIR/command-outcome-tests" "$mode"
done
xcrun swiftc -typecheck \
    -import-objc-header Sources/EeveeSpotifyC/include/CommandOutcomeDiagnostics.h \
    Tests/CommandOutcomeDiagnostics/bridge.swift
