// ReinventFreeBlocker: block the "ReinventFree" services that impose Free-tier
// playback restrictions (shuffle-only, no seek, no queue, time caps, etc.).
//
// Spotify 9.2.0 removed the HTTP bootstrap/v1/bootstrap and /v1/customize
// endpoints entirely.  Product state now arrives via the C++ Esperanto RPC
// layer (spotify.product_state.esperanto.proto) and is read by the player
// core through a C++ shared_ptr<ProductState>, bypassing the ObjC
// SPTCoreProductState hooks that EeveePremiumForce uses.
//
// Because the player core's licence check can no longer be intercepted at the
// HTTP or ObjC level, the pragmatic fix is to prevent the Free-tier UX
// modules from loading at all.  These "ReinventFree_*" SPTService classes
// are what turn the player into shuffle-only/no-seek mode; starving their
// `load` makes the player fall back to the unrestricted (premium) UX path.
//
// Every hook is runtime-gated (class + selector check) so older builds that
// lack a given service degrade gracefully, identical to
// EeveeAdBlockerExtended.x.swift.

import Orion
import Foundation
import ObjectiveC.runtime

// Each service gets its own group so one missing class doesn't block the rest.
struct ReinventFreeControllerGroup: HookGroup {}
struct ReinventFreeControllerUIGroup: HookGroup {}
struct ReinventFreeFMARestrictionsGroup: HookGroup {}
struct ReinventFreeOnDemandUIGroup: HookGroup {}
struct ReinventFreeNpvGroup: HookGroup {}
struct ReinventFreeStepDownCapGroup: HookGroup {}
struct ReinventFreeTimeCapPivotGroup: HookGroup {}
struct ReinventFreePlayFullSongGroup: HookGroup {}
struct ReinventFreeAdUnlockGroup: HookGroup {}
struct ReinventFreeCtxUpsellPromoGroup: HookGroup {}
struct ReinventFreeDownloadUpsellGroup: HookGroup {}
struct ReinventFreeTopUpGroup: HookGroup {}

private func rflog(_ msg: String) {
    writeDebugLog("[ReinventFreeBlocker] \(msg)")
}

// ── Service kills ──────────────────────────────────────────────────────

class ReinventFreeServiceKill: ClassHook<NSObject> {
    typealias Group = ReinventFreeControllerGroup
    static let targetName = "_TtC27ReinventFree_ControllerImpl19ReinventFreeService"
    func load() { rflog("suppressed ReinventFreeService.load") }
}

class ControllerUIServiceKill: ClassHook<NSObject> {
    typealias Group = ReinventFreeControllerUIGroup
    static let targetName = "_TtC29ReinventFree_ControllerUIImpl19ControllerUIService"
    func load() { rflog("suppressed ControllerUIService.load") }
}

class FMARestrictionsServiceKill: ClassHook<NSObject> {
    typealias Group = ReinventFreeFMARestrictionsGroup
    static let targetName = "_TtC32ReinventFree_FMARestrictionsImpl26FMARestrictionsServiceImpl"
    func load() { rflog("suppressed FMARestrictionsServiceImpl.load") }
}

class OnDemandUIServiceKill: ClassHook<NSObject> {
    typealias Group = ReinventFreeOnDemandUIGroup
    static let targetName = "_TtC27ReinventFree_OnDemandUIImpl21OnDemandUIServiceImpl"
    func load() { rflog("suppressed OnDemandUIServiceImpl.load") }
}

class ReinventFreeNpvServiceKill: ClassHook<NSObject> {
    typealias Group = ReinventFreeNpvGroup
    static let targetName = "_TtC32ReinventFree_ReinventFreeNpvImpl22ReinventFreeNpvService"
    func load() { rflog("suppressed ReinventFreeNpvService.load") }
}

class StepDownCapServiceKill: ClassHook<NSObject> {
    typealias Group = ReinventFreeStepDownCapGroup
    static let targetName = "_TtC28ReinventFree_StepDownCapImpl22StepDownCapServiceImpl"
    func load() { rflog("suppressed StepDownCapServiceImpl.load") }
}

class TimeCapPivotServiceKill: ClassHook<NSObject> {
    typealias Group = ReinventFreeTimeCapPivotGroup
    static let targetName = "_TtC29ReinventFree_TimeCapPivotImpl33TimeCapPivotServiceImplementation"
    func load() { rflog("suppressed TimeCapPivotServiceImplementation.load") }
}

class RFPlayFullSongUpsellServiceKill: ClassHook<NSObject> {
    typealias Group = ReinventFreePlayFullSongGroup
    static let targetName = "_TtC35ReinventFree_PlayFullSongUpsellImpl29PlayFullSongUpsellServiceImpl"
    func load() { rflog("suppressed PlayFullSongUpsellServiceImpl.load") }
}

class AdUnlockEligibilityServiceKill: ClassHook<NSObject> {
    typealias Group = ReinventFreeAdUnlockGroup
    static let targetName = "_TtC36ReinventFree_AdUnlockEligibilityImpl40AdUnlockEligibilityServiceImplementation"
    func load() { rflog("suppressed AdUnlockEligibilityServiceImplementation.load") }
}

class CtxUpsellPremiumPromoServiceKill: ClassHook<NSObject> {
    typealias Group = ReinventFreeCtxUpsellPromoGroup
    static let targetName = "_TtC45ReinventFree_ContextualUpsellPremiumPromoImpl39ContextualUpsellPremiumPromoServiceImpl"
    func load() { rflog("suppressed ContextualUpsellPremiumPromoServiceImpl.load") }
}

class RFDownloadUpsellServiceKill: ClassHook<NSObject> {
    typealias Group = ReinventFreeDownloadUpsellGroup
    static let targetName = "_TtC31ReinventFree_DownloadUpsellImpl21DownloadUpsellService"
    func load() { rflog("suppressed DownloadUpsellService.load") }
}

class TopUpEligibilityServiceKill: ClassHook<NSObject> {
    typealias Group = ReinventFreeTopUpGroup
    static let targetName = "_TtC33ReinventFree_TopUpEligibilityImpl27TopUpEligibilityServiceImpl"
    func load() { rflog("suppressed TopUpEligibilityServiceImpl.load") }
}

// ── Activation ─────────────────────────────────────────────────────────

func activateReinventFreeBlocker() {
    let loadSelector = Selector(("load"))

    let targets: [(String, String, () -> Void)] = [
        (ReinventFreeServiceKill.targetName, "ReinventFreeService", { ReinventFreeControllerGroup().activate() }),
        (ControllerUIServiceKill.targetName, "ControllerUIService", { ReinventFreeControllerUIGroup().activate() }),
        (FMARestrictionsServiceKill.targetName, "FMARestrictionsServiceImpl", { ReinventFreeFMARestrictionsGroup().activate() }),
        (OnDemandUIServiceKill.targetName, "OnDemandUIServiceImpl", { ReinventFreeOnDemandUIGroup().activate() }),
        (ReinventFreeNpvServiceKill.targetName, "ReinventFreeNpvService", { ReinventFreeNpvGroup().activate() }),
        (StepDownCapServiceKill.targetName, "StepDownCapServiceImpl", { ReinventFreeStepDownCapGroup().activate() }),
        (TimeCapPivotServiceKill.targetName, "TimeCapPivotServiceImplementation", { ReinventFreeTimeCapPivotGroup().activate() }),
        (RFPlayFullSongUpsellServiceKill.targetName, "PlayFullSongUpsellServiceImpl", { ReinventFreePlayFullSongGroup().activate() }),
        (AdUnlockEligibilityServiceKill.targetName, "AdUnlockEligibilityServiceImplementation", { ReinventFreeAdUnlockGroup().activate() }),
        (CtxUpsellPremiumPromoServiceKill.targetName, "ContextualUpsellPremiumPromoServiceImpl", { ReinventFreeCtxUpsellPromoGroup().activate() }),
        (RFDownloadUpsellServiceKill.targetName, "DownloadUpsellService", { ReinventFreeDownloadUpsellGroup().activate() }),
        (TopUpEligibilityServiceKill.targetName, "TopUpEligibilityServiceImpl", { ReinventFreeTopUpGroup().activate() }),
    ]

    var activated = 0
    for (className, label, activate) in targets {
        guard let cls = findTweakClass(className) else {
            rflog("\(label) unavailable: class not registered")
            continue
        }
        guard class_getInstanceMethod(cls, loadSelector) != nil else {
            rflog("\(label) unavailable: no load selector")
            continue
        }
        activate()
        activated += 1
        rflog("\(label) hook activated")
    }

    rflog("activated \(activated)/\(targets.count) ReinventFree service kills")

    // ── Player restriction override ────────────────────────────────────
    // SPTPlayerRestrictions (and its backing classes) are Swift types that
    // may or may not register in the ObjC runtime.  Scan all registered
    // classes for the restriction selectors the C++ player exposes and
    // swizzle every Bool getter to return true (= unrestricted).
    let restrictionSelectors = [
        "canSeek",
        "canSkipNext",
        "canSkipPrev",
        "canAddToQueue",
        "canToggleShuffle",
        "canRepeatContext",
        "canRepeatTrack",
    ]

    // Selectors that should return false to disable free-tier behavior
    let invertSelectors = [
        "isPlaybackRestricted",
        "shouldApplyFMARestrictions",
        "isFreeTierEnabled",
        "isFreeTierUser",
        "isFreeUser",
        "isFreeExperienceEnabled",
    ]

    let total = objc_getClassList(nil, 0)
    guard total > 0 else { rflog("objc_getClassList returned 0"); return }
    let buf = UnsafeMutablePointer<AnyClass>.allocate(capacity: Int(total))
    defer { buf.deallocate() }
    let n = objc_getClassList(AutoreleasingUnsafeMutablePointer<AnyClass>(buf), total)

    var swizzled = 0
    for i in 0..<Int(n) {
        let raw = UnsafeRawPointer(buf).load(
            fromByteOffset: i * MemoryLayout<UnsafeRawPointer>.size,
            as: UnsafeRawPointer.self
        )
        let cls: AnyClass = unsafeBitCast(raw, to: AnyClass.self)
        let name = String(cString: class_getName(cls))

        // Only touch Spotify's own classes (avoid Foundation/UIKit)
        guard name.hasPrefix("SPT") || name.hasPrefix("_Tt") else { continue }

        for sel in restrictionSelectors {
            let selector = NSSelectorFromString(sel)
            guard let method = class_getInstanceMethod(cls, selector) else { continue }
            // Only swizzle Bool (B) return type
            guard let typeStr = method_getTypeEncoding(method),
                  String(cString: typeStr).hasPrefix("B") else { continue }
            let block: @convention(block) (AnyObject) -> Bool = { _ in true }
            let imp = imp_implementationWithBlock(block)
            method_setImplementation(method, imp)
            rflog("swizzled \(name).\(sel) → true")
            swizzled += 1
        }

        for sel in invertSelectors {
            let selector = NSSelectorFromString(sel)
            guard let method = class_getInstanceMethod(cls, selector) else { continue }
            guard let typeStr = method_getTypeEncoding(method),
                  String(cString: typeStr).hasPrefix("B") else { continue }
            let block: @convention(block) (AnyObject) -> Bool = { _ in false }
            let imp = imp_implementationWithBlock(block)
            method_setImplementation(method, imp)
            rflog("swizzled \(name).\(sel) → false")
            swizzled += 1
        }
    }

    rflog("swizzled \(swizzled) player restriction methods")
}
