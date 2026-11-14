// VersionHookTarget selection tests
// Verifies the numeric version comparison that decides hookTarget.
// Mirrors the logic in EeveeSpotify.hookTarget without importing Orion.

import Foundation

enum VersionHookTarget: String {
    case v90
    case lastAvailableiOS15
    case v91
    case lastAvailableiOS14
}

func hookTarget(for version: String) -> VersionHookTarget {
    switch version {
    case "9.0.48":
        return .lastAvailableiOS15
    case "8.9.8":
        return .lastAvailableiOS14
    default:
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else {
            return .v91
        }
        let (major, minor) = (parts[0], parts[1])
        if major > 9 || (major == 9 && minor >= 1) {
            return .v91
        }
        return .v90
    }
}

var passed = 0
var failed = 0

func expect(_ version: String, _ expected: VersionHookTarget,
            file: String = #file, line: Int = #line) {
    let got = hookTarget(for: version)
    if got == expected {
        passed += 1
    } else {
        print("FAIL (\(file):\(line)): \"\(version)\" expected .\(expected.rawValue), got .\(got.rawValue)")
        failed += 1
    }
}

// Pinned builds
expect("8.9.8", .lastAvailableiOS14)
expect("9.0.48", .lastAvailableiOS15)

// Pre-9.1 builds go to .v90
expect("8.9.2", .v90)
expect("9.0.0", .v90)
expect("9.0.99", .v90)

// 9.1.x builds go to .v91
expect("9.1.0", .v91)
expect("9.1.28", .v91)
expect("9.1.84", .v91)

// 9.2.x and later go to .v91 (the fix)
expect("9.2.0", .v91)
expect("9.2.5", .v91)
expect("9.10.0", .v91)

// Future major versions
expect("10.0.0", .v91)
expect("11.3.2", .v91)

// Edge case: "8.9.10".contains("9.1") was true with the old check — now correctly .v90
expect("8.9.10", .v90)
expect("8.9.18", .v90)

// Unparseable version defaults to .v91
expect("unknown", .v91)
expect("", .v91)

print("VersionHookTarget: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }
