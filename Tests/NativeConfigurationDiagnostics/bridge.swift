// Type-check the same C callback import used by Tweak.x.swift.
EEVInstallNativeConfigDiagnostics { message in
    _ = String(cString: message)
}
EEVNativeConfigDiagnosticsSummary()
