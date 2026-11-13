#ifndef EEV_COMMAND_OUTCOME_DIAGNOSTICS_H
#define EEV_COMMAND_OUTCOME_DIAGNOSTICS_H
#import "NativeConfigDiagnostics.h"
#ifdef __cplusplus
extern "C" {
#endif
void EEVInstallCommandOutcomeDiagnostics(const char * _Nonnull version,
    EEVConfigDiagnosticLogger _Nonnull logger);
#ifdef __cplusplus
}
#endif
#endif
