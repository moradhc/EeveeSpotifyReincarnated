import Foundation

// No NSNumber coercion: a bool assignment cannot replace an integer, or vice versa.
enum ConfigurationReadValue: Equatable {
    case bool(Bool)
    case integer(Int)
    case choice(String)
}

enum ConfigurationReadPolicy {
    static func enabled(version: String, patching: Bool, overwrite: Bool) -> Bool {
        version == "9.2.0" && patching && overwrite
    }

    static func bool(_ value: ConfigurationReadValue?) -> Bool? {
        guard case .bool(let result)? = value else { return nil }
        return result
    }

    static func integer(_ value: ConfigurationReadValue?, lower: Int, upper: Int) -> Int? {
        guard lower <= upper, case .integer(let result)? = value,
              result >= lower, result <= upper else { return nil }
        return result
    }

    static func choice(_ value: ConfigurationReadValue?, options: [String]) -> String? {
        guard case .choice(let result)? = value, options.contains(result) else { return nil }
        return result
    }

    static let preservedKeys: Set<String> = [
        "ios-campfire-properties-impl.campfire_feature_enabled",
        "ios-feature-sidedrawer-platform.is_list_page_enabled"
    ]

    static func index(_ entries: [(String, ConfigurationReadValue)]) -> [String: ConfigurationReadValue] {
        var result: [String: ConfigurationReadValue] = [:]
        var duplicates = Set<String>()
        for (key, value) in entries where !preservedKeys.contains(key) && !key.isEmpty {
            if result[key] != nil { duplicates.insert(key) }
            result[key] = value
        }
        // Ambiguous snapshots are not resolved by arbitrary iteration order.
        for key in duplicates { result.removeValue(forKey: key) }
        return result
    }
}
