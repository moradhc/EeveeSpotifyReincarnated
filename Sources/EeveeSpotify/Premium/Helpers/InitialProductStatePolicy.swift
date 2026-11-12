import Foundation

/// A narrowly scoped write at the initializer observed in the 9.1.98 trace.
/// Reads remain untouched so diagnostics can detect subsequent reversion.
enum InitialProductStatePolicy {
    struct Result {
        let dictionary: NSDictionary
        let changedKeys: [String]
        let reason: String
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
        let replacements: [(String, String)] = [
            ("type", "premium"),
            ("catalogue", "premium"),
            ("ads", "0"),
            ("on-demand", "1"),
            ("shuffle", "0"),
            ("player-license", "premium"),
        ]
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
