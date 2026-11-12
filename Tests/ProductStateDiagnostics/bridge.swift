import Foundation

// Typecheck exactly the Foundation bridges used by the Orion hooks.
func checkProductStateBridge(_ dict: NSDictionary, _ key: NSString, _ value: Any?) {
    EEVStartProductStateDiagnostics { message in _ = String(cString: message) }
    EEVProductStateDictionary("set-original", dict, dict)
    EEVProductStateGetter("string-getter", key as String, value, false)
    EEVProductStateGetter("string-getter", key as String, "premium" as NSString, true)
    EEVProductStateAds(false, true)
    EEVInstallProductStateBridgeProbe()
    EEVProductStateSummary()
}
