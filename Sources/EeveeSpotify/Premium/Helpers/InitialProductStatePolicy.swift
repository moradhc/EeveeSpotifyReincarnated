import Foundation

/// Correct the initial snapshot and subsequent observed dictionaries for the
/// same instance. This does not write into a C++ object or a remote account.
enum InitialProductStatePolicy {
    struct Result {
        let dictionary: NSDictionary
        let changedKeys: [String]
        let reason: String
    }

    private static let replacements: [(String, String)] = [
        ("type", "premium"), ("catalogue", "premium"), ("ads", "0"),
        ("on-demand", "1"), ("shuffle", "0"), ("player-license", "premium"),
    ]

    static func existingKeys(in dictionary: NSDictionary) -> [String] {
        replacements.compactMap { key, _ in dictionary[key] is String ? key : nil }
    }

    /// Update dictionaries may contain only ads/shuffle, without type/catalogue.
    /// Registration at initialization provides the scope; missing keys stay absent.
    static func rewriteUpdate(
        _ dictionary: NSDictionary,
        protectedKeys: [String],
        spotifyVersion: String,
        patchingEnabled: Bool
    ) -> Result {
        guard patchingEnabled else {
            return Result(dictionary: dictionary, changedKeys: [], reason: "patching-disabled")
        }
        guard spotifyVersion == "9.1.98" else {
            return Result(dictionary: dictionary, changedKeys: [], reason: "unsupported-version")
        }
        let selected = replacements.filter { protectedKeys.contains($0.0) }
        guard !selected.isEmpty else {
            return Result(dictionary: dictionary, changedKeys: [], reason: "unprotected-instance")
        }
        for (key, _) in selected {
            if let value = dictionary[key], !(value is String) {
                return Result(dictionary: dictionary, changedKeys: [], reason: "unexpected-value-type")
            }
        }
        let changed = selected.filter { key, desired in
            guard let current = dictionary[key] as? String else { return false }
            return current != desired
        }
        guard !changed.isEmpty else {
            return Result(dictionary: dictionary, changedKeys: [], reason: "unchanged")
        }
        let output = dictionary.mutableCopy() as! NSMutableDictionary
        for (key, value) in changed { output[key] = value }
        return Result(dictionary: output.copy() as! NSDictionary,
                      changedKeys: changed.map { $0.0 }, reason: "applied-update")
    }

    static func rewrite(
        _ dictionary: NSDictionary,
        spotifyVersion: String,
        patchingEnabled: Bool
    ) -> Result {
        guard patchingEnabled else {
            return Result(dictionary: dictionary, changedKeys: [], reason: "patching-disabled")
        }
        guard spotifyVersion == "9.1.98" else {
            return Result(dictionary: dictionary, changedKeys: [], reason: "unsupported-version")
        }
        guard dictionary["type"] as? String == "free"
                || dictionary["catalogue"] as? String == "free" else {
            return Result(dictionary: dictionary, changedKeys: [], reason: "not-free")
        }

        // Only keys present in the supplied snapshot are replaced. Do not seed
        // product/unrestricted, strip keys, or alter streaming rules, country,
        // subscription dates, session/logout fields, or other account data.
        for (key, _) in replacements {
            if let value = dictionary[key], !(value is String) {
                return Result(dictionary: dictionary, changedKeys: [], reason: "unexpected-value-type")
            }
        }

        let output = dictionary.mutableCopy() as! NSMutableDictionary
        var changedKeys: [String] = []
        for (key, value) in replacements {
            guard let previous = dictionary[key] as? String, previous != value else { continue }
            output[key] = value
            changedKeys.append(key)
        }
        return Result(
            dictionary: output.copy() as! NSDictionary,
            changedKeys: changedKeys,
            reason: "applied"
        )
    }
}
