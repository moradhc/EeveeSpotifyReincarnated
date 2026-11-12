#ifndef EEV_NATIVE_CONFIG_DIAGNOSTICS_H
#define EEV_NATIVE_CONFIG_DIAGNOSTICS_H

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*EEVConfigDiagnosticLogger)(const char * _Nonnull message);
void EEVInstallNativeConfigDiagnostics(EEVConfigDiagnosticLogger _Nonnull logger);
void EEVNativeConfigDiagnosticsSummary(void);

#ifdef __cplusplus
}
#endif
#endif
