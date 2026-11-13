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

// V6 regression: a later notification reintroduces the same six Free values.
let protectedKeys = InitialProductStatePolicy.existingKeys(in: input)
let update = InitialProductStatePolicy.rewriteUpdate(input, protectedKeys: protectedKeys,
                                                    spotifyVersion: "9.1.98", patchingEnabled: true)
require(update.dictionary.isEqual(expected) && input.isEqual(originalCopy),
        "late Free notification must be corrected without mutating its input")
let delta: NSDictionary = ["ads": "1", "shuffle": "1", "country": "ES"]
let correctedDelta = InitialProductStatePolicy.rewriteUpdate(delta, protectedKeys: protectedKeys,
                                                            spotifyVersion: "9.1.98", patchingEnabled: true)
require(correctedDelta.dictionary.isEqual(["ads": "0", "shuffle": "0", "country": "ES"] as NSDictionary),
        "partial notifications must work without type/catalogue and must not seed missing keys")
let correctedAgain = InitialProductStatePolicy.rewriteUpdate(correctedDelta.dictionary, protectedKeys: protectedKeys,
                                                            spotifyVersion: "9.1.98", patchingEnabled: true)
require(correctedAgain.dictionary === correctedDelta.dictionary && correctedAgain.changedKeys.isEmpty,
        "nested dictionary reads must be idempotent")
let unrelated: NSDictionary = ["country": "ES", "future-unknown-key": "fixture-unknown"]
let unrelatedResult = InitialProductStatePolicy.rewriteUpdate(unrelated, protectedKeys: protectedKeys + ["country"],
                                                            spotifyVersion: "9.1.98", patchingEnabled: true)
require(unrelatedResult.dictionary === unrelated, "protected keys must never expand the six-key allowlist")
for (version, enabled, keys) in [("9.1.98", false, protectedKeys), ("9.1.99", true, protectedKeys), ("9.1.98", true, [])] {
    let skipped = InitialProductStatePolicy.rewriteUpdate(input, protectedKeys: keys,
                                                        spotifyVersion: version, patchingEnabled: enabled)
    require(skipped.dictionary === input && skipped.changedKeys.isEmpty, "update scope/mode/version gate bypassed")
}
let limited = InitialProductStatePolicy.rewriteUpdate(input, protectedKeys: ["ads"],
                                                    spotifyVersion: "9.1.98", patchingEnabled: true)
require(limited.dictionary["type"] as? String == "free" && limited.changedKeys == ["ads"],
        "update must change only attributes registered at initialization")
let deletion: NSDictionary = ["type": NSNull(), "ads": "1"]
let deletionResult = InitialProductStatePolicy.rewriteUpdate(deletion, protectedKeys: protectedKeys,
                                                           spotifyVersion: "9.1.98", patchingEnabled: true)
require(deletionResult.dictionary === deletion && deletionResult.reason == "unexpected-value-type",
        "unknown/deletion representation must not produce a partial rewrite")

print("Product state policy: initialization, late/partial updates, scope, idempotence and preservation passed")
