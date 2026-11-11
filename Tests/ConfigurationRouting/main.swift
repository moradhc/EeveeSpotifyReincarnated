import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAIL: \(message)") }
}

// The same configuration request must reach the response parser on a fresh
// launch and after the 30-second startup grace period. Cache availability must
// not turn a valid response into an empty synthetic advertising response.
let elapsedTimes: [TimeInterval] = [0, 29, 30, 31, 300]
for elapsed in elapsedTimes {
    for path in ["/bootstrap/v1/bootstrap", "/ucs/v1/customize"] {
        let url = URL(string: "https://gew1-spclient.spotify.com\(path)")!
        require(!SpotifyRequestRouting.shouldBlock(url, elapsed: elapsed),
                "configuration blocked at \(elapsed)s: \(path)")
    }

    for path in ["/ads/v3/ads", "/ad-logic/prefetch", "/ad-logic/v3/config"] {
        let url = URL(string: "https://gew1-spclient.spotify.com\(path)")!
        require(SpotifyRequestRouting.shouldBlock(url, elapsed: elapsed),
                "existing ad policy changed: \(path)")
    }
    let libraryURL = URL(string: "https://gew1-spclient.spotify.com/collection/v1/library/items")!
    require(!SpotifyRequestRouting.shouldBlock(libraryURL, elapsed: elapsed),
            "ordinary library request blocked")
}

let signupURL = URL(string: "https://spclient.wg.spotify.com/signup/public/v1/account")!
require(!SpotifyRequestRouting.shouldBlock(signupURL, elapsed: 30),
        "existing startup grace period shortened")
require(SpotifyRequestRouting.shouldBlock(signupURL, elapsed: 31),
        "unrelated post-startup policy changed")

// Regression guard for two Orion hooks consuming one destructive task buffer.
let modern = try String(contentsOfFile: "Sources/EeveeSpotify/DataLoaderServiceHooks.x.swift", encoding: .utf8)
let legacy = try String(contentsOfFile: "Sources/EeveeSpotify/Premium/DynamicPremium+ModifyBootstrap.x.swift", encoding: .utf8)
require(modern.contains("typealias Group = PremiumBootstrapGroup"),
        "modern delegate must belong to the modern bootstrap group")
require(legacy.contains("typealias Group = LegacyPremiumBootstrapGroup"),
        "legacy delegate must not activate with the modern bootstrap group")
require(!legacy.contains("typealias Group = PremiumBootstrapGroup"),
        "duplicate bootstrap buffer consumer reintroduced")

print("Configuration routing regression tests passed (32 routing cases + hook ownership guards)")
