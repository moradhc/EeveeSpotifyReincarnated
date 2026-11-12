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
