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
}
