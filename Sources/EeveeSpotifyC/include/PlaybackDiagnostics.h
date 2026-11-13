#ifndef EEV_PLAYBACK_DIAGNOSTICS_H
#define EEV_PLAYBACK_DIAGNOSTICS_H
#import "NativeConfigDiagnostics.h"
#ifdef __cplusplus
extern "C" {
#endif
void EEVInstallPlaybackDiagnostics(EEVConfigDiagnosticLogger _Nonnull logger);
void EEVPlaybackDiagnosticsSummary(void);
#ifdef __cplusplus
}
#endif
#endif
