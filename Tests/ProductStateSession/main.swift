import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAIL: \(message)") }
}

let first = NSObject()
let second = NSObject()
require(ProductStateSession.keys(for: first).isEmpty, "an unregistered instance must remain inactive")
var selected = ["type", "ads"]
ProductStateSession.register(first, keys: selected)
selected.append("country")
require(ProductStateSession.keys(for: first) == ["type", "ads"], "registered scope must be a value snapshot")
require(ProductStateSession.keys(for: second).isEmpty, "registration must not leak to other instances")

let update: NSDictionary = ["type": "free", "ads": "1", "country": "ES"]
let firstResult = InitialProductStatePolicy.rewriteUpdate(update, protectedKeys: ProductStateSession.keys(for: first),
                                                         spotifyVersion: "9.1.98", patchingEnabled: true)
let secondResult = InitialProductStatePolicy.rewriteUpdate(update, protectedKeys: ProductStateSession.keys(for: second),
                                                          spotifyVersion: "9.1.98", patchingEnabled: true)
require(firstResult.dictionary.isEqual(["type": "premium", "ads": "0", "country": "ES"] as NSDictionary),
        "registered instance must correct its later update")
require(secondResult.dictionary === update, "other state instances must preserve their update")
ProductStateSession.register(first, keys: [])
require(ProductStateSession.keys(for: first).isEmpty, "registration must be replaceable")
print("ProductStateSession: per-instance isolation and update integration passed")
