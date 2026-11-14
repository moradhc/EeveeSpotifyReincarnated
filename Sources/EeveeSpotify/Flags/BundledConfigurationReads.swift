import Foundation

// Consumer-side fallback for 9.2.0. This is not a UCS transport hook and does not
// rewrite account attributes or configuration read directly by C++/Swift code.
enum BundledConfigurationReads {
    private static var assignments: [String: ConfigurationReadValue] = [:]
    private static let lock = NSLock()
    private static var reads = 0
    private static var matched = 0
    private static var compatible = 0
    private static var changed = 0
    private static var summaryScheduled = false

    static var enabled: Bool {
        ConfigurationReadPolicy.enabled(version: EeveeSpotify.spotifyVersion,
            patching: UserDefaults.patchType.isPatching, overwrite: UserDefaults.overwriteConfiguration)
    }

    // Called once at startup, before the provider hooks are activated.
    static func prepare() {
        guard enabled else { return }
        do {
            var values = try BundleHelper.shared.resolveConfiguration().assignedValues
            modifyAssignedValues(&values)
            let entries: [(String, ConfigurationReadValue)] = values.compactMap { assignment in
                guard assignment.hasPropertyID, !assignment.propertyID.scope.isEmpty,
                      !assignment.propertyID.name.isEmpty else { return nil }
                let key = "\(assignment.propertyID.scope).\(assignment.propertyID.name)"
                switch assignment.structuredValue {
                case .boolValue(let value)?: return (key, .bool(value.value))
                case .intValue(let value)?: return (key, .integer(Int(value.value)))
                case .enumValue(let value)?: return (key, .choice(value.value))
                case nil: return nil
                }
            }
            assignments = ConfigurationReadPolicy.index(entries)
            writeDebugLog("[CONFIG V16] consumer snapshot loaded assignments=\(assignments.count)")
        } catch {
            writeDebugLog("[CONFIG V16] consumer snapshot unavailable code=\((error as NSError).code); live values retained")
        }
    }

    private static func record(_ key: String, found: Bool, accepted: Bool, different: Bool) {
        lock.lock()
        reads += 1
        if found { matched += 1 }
        if accepted { compatible += 1 }
        if different { changed += 1 }
        let reportChange = different && changed <= 12
        let schedule = !summaryScheduled
        summaryScheduled = true
        lock.unlock()
        // Property identifiers only, never values, tokens or account identifiers.
        if reportChange { writeDebugLog("[CONFIG V16] consumer changed key=\(key)") }
        if schedule {
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                lock.lock()
                let counts = (reads, matched, compatible, changed)
                lock.unlock()
                writeDebugLog("[CONFIG V16] consumer summary reads=\(counts.0) matched=\(counts.1) compatible=\(counts.2) changed=\(counts.3)")
            }
        }
    }

    static func bool(_ key: String, original: Bool) -> Bool {
        guard enabled else { return original }
        let value = assignments[key]
        let replacement = ConfigurationReadPolicy.bool(value)
        record(key, found: value != nil, accepted: replacement != nil,
               different: replacement.map { $0 != original } ?? false)
        return replacement ?? original
    }

    static func integer(_ key: String, lower: Int, upper: Int, original: Int) -> Int {
        guard enabled else { return original }
        let value = assignments[key]
        let replacement = ConfigurationReadPolicy.integer(value, lower: lower, upper: upper)
        record(key, found: value != nil, accepted: replacement != nil,
               different: replacement.map { $0 != original } ?? false)
        return replacement ?? original
    }

    static func choice(_ key: String, options: [String], original: AnyObject) -> AnyObject {
        guard enabled else { return original }
        let value = assignments[key]
        let replacement = ConfigurationReadPolicy.choice(value, options: options)
        record(key, found: value != nil, accepted: replacement != nil,
               different: replacement.map { (original as? String) != $0 } ?? false)
        guard let replacement = replacement else { return original }
        return replacement as NSString
    }
}
