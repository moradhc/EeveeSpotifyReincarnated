import Foundation

assert(ConfigurationReadPolicy.enabled(version: "9.2.0", patching: true, overwrite: true))
assert(!ConfigurationReadPolicy.enabled(version: "9.2.1", patching: true, overwrite: true))
assert(!ConfigurationReadPolicy.enabled(version: "9.2.0", patching: false, overwrite: true))
assert(!ConfigurationReadPolicy.enabled(version: "9.2.0", patching: true, overwrite: false))
assert(ConfigurationReadPolicy.bool(.bool(false)) == false)
assert(ConfigurationReadPolicy.bool(.integer(0)) == nil)
assert(ConfigurationReadPolicy.bool(nil) == nil)
assert(ConfigurationReadPolicy.integer(.integer(7), lower: 0, upper: 5) == nil)
assert(ConfigurationReadPolicy.integer(.integer(3), lower: 0, upper: 5) == 3)
assert(ConfigurationReadPolicy.integer(.integer(3), lower: 5, upper: 0) == nil)
assert(ConfigurationReadPolicy.integer(.bool(true), lower: 0, upper: 5) == nil)
assert(ConfigurationReadPolicy.choice(.choice("old"), options: ["new"]) == nil)
assert(ConfigurationReadPolicy.choice(.choice("new"), options: ["new"]) == "new")
let index = ConfigurationReadPolicy.index([
    ("a.bool", .bool(true)), ("dup", .integer(1)), ("dup", .integer(2)),
    ("ios-campfire-properties-impl.campfire_feature_enabled", .bool(false)),
    ("ios-feature-sidedrawer-platform.is_list_page_enabled", .bool(false)),
    ("", .bool(true))
])
assert(index == ["a.bool": .bool(true)])
print("ConfigurationReadOverride: PASS")
