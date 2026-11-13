import Foundation
func checkPlaybackBridge() {
    EEVInstallPlaybackDiagnostics { message in _ = String(cString: message) }
    EEVPlaybackDiagnosticsSummary()
}
