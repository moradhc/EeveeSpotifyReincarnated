#ifndef EEV_NATIVE_PLAYBACK_FIX_H
#define EEV_NATIVE_PLAYBACK_FIX_H
#include <stdbool.h>
#import "NativeConfigDiagnostics.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef bool (*EEVNativePlaybackEnabled)(void);
void EEVInstallNativePlaybackFix(EEVNativePlaybackEnabled _Nonnull enabled,
    EEVConfigDiagnosticLogger _Nonnull logger);
#ifdef __cplusplus
}
#endif
#endif
