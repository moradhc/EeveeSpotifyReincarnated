import Foundation
import ObjectiveC

/// An instance is registered only after V5 successfully corrects its initializer.
/// Associated storage avoids global state leaking between separate state objects.
enum ProductStateSession {
    private static var associationKey: UInt8 = 0

    static func register(_ object: NSObject, keys: [String]) {
        objc_setAssociatedObject(object, &associationKey, keys as NSArray, .OBJC_ASSOCIATION_RETAIN)
    }

    static func keys(for object: NSObject) -> [String] {
        objc_getAssociatedObject(object, &associationKey) as? [String] ?? []
    }
}
