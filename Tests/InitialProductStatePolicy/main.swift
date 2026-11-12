import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAIL: \(message)") }
}

// Relevant fields from the observed V4 snapshot. The raw player-license was
// redacted in that log; use a synthetic string to test the replacement path.
let input: NSDictionary = [
    "type": "free", "catalogue": "free", "ads": "1",
    "on-demand": "0", "shuffle": "1", "player-license": "fixture-license",
    "country": "ES", "streaming-rules": "fixture-rules",
    "previous-streaming-rules": "fixture-previous-rules",
    "forced_logout": "fixture-logout", "subscription-enddate": "fixture-date",
    "payment-state": "fixture-payment", "future-unknown-key": "fixture-unknown",
]
let originalCopy = input.copy() as! NSDictionary
let result = InitialProductStatePolicy.rewrite(input, spotifyVersion: "9.1.98", patchingEnabled: true)
let expected: NSDictionary = [
    "type": "premium", "catalogue": "premium", "ads": "0",
    "on-demand": "1", "shuffle": "0", "player-license": "premium",
    "country": "ES", "streaming-rules": "fixture-rules",
    "previous-streaming-rules": "fixture-previous-rules",
    "forced_logout": "fixture-logout", "subscription-enddate": "fixture-date",
    "payment-state": "fixture-payment", "future-unknown-key": "fixture-unknown",
]
require(result.reason == "applied" && result.dictionary.isEqual(expected),
        "observed Free snapshot must be corrected without changing unrelated fields")
require(input.isEqual(originalCopy), "input snapshot must not be mutated")
require(result.changedKeys.count == 6 && result.dictionary.count == input.count,
        "only six existing attributes may change; absent attributes must not be added")

let repeated = InitialProductStatePolicy.rewrite(result.dictionary, spotifyVersion: "9.1.98", patchingEnabled: true)
require(repeated.dictionary === result.dictionary && repeated.changedKeys.isEmpty,
        "an already corrected snapshot must pass through unchanged")

let disabled = InitialProductStatePolicy.rewrite(input, spotifyVersion: "9.1.98", patchingEnabled: false)
require(disabled.dictionary === input && disabled.reason == "patching-disabled", "disabled patch mode must preserve identity and contents")
for version in ["9.1.88", "9.1.97", "9.1.99", "9.1.980", "9.1.98.1", "?"] {
    let skipped = InitialProductStatePolicy.rewrite(input, spotifyVersion: version, patchingEnabled: true)
    require(skipped.dictionary === input && skipped.reason == "unsupported-version", "unsupported version must pass through")
}

let otherStates: [NSDictionary] = [[:], ["type": "premium", "ads": "0"], ["type": "unknown-plan", "ads": "1"]]
for other in otherStates {
    let skipped = InitialProductStatePolicy.rewrite(other, spotifyVersion: "9.1.98", patchingEnabled: true)
    require(skipped.dictionary === other && skipped.changedKeys.isEmpty, "unrecognized or non-Free state must pass through")
}

let partial: NSDictionary = ["catalogue": "free", "ads": "1", "country": "ES"]
let partialResult = InitialProductStatePolicy.rewrite(partial, spotifyVersion: "9.1.98", patchingEnabled: true)
require(partialResult.dictionary.isEqual(["catalogue": "premium", "ads": "0", "country": "ES"] as NSDictionary),
        "partial snapshots must preserve absent keys")

let invalidValues: [Any] = [NSNumber(value: 1), NSNull(), ["unexpected": "object"]]
for invalid in invalidValues {
    let malformed: NSDictionary = ["type": "free", "ads": invalid]
    let skipped = InitialProductStatePolicy.rewrite(malformed, spotifyVersion: "9.1.98", patchingEnabled: true)
    require(skipped.dictionary === malformed && skipped.reason == "unexpected-value-type",
            "unexpected attribute types must not produce a partially rewritten snapshot")
}

let mutable = input.mutableCopy() as! NSMutableDictionary
let detached = InitialProductStatePolicy.rewrite(mutable, spotifyVersion: "9.1.98", patchingEnabled: true)
mutable["type"] = "later-change"
require(detached.dictionary["type"] as? String == "premium", "later input mutation must not change output")

print("InitialProductStatePolicy: observed snapshot, field preservation, idempotence, version/mode gates and unexpected types passed")
