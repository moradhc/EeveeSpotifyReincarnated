#ifndef EEV_PLAYBACK_RESTRICTION_POLICY_H
#define EEV_PLAYBACK_RESTRICTION_POLICY_H
#include <stdbool.h>
#import "NativeConfigDiagnostics.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef bool (*EEVPlaybackPolicyEnabled)(void);
void EEVInstallPlaybackRestrictionPolicy(const char * _Nonnull version,
    EEVPlaybackPolicyEnabled _Nonnull enabled,
    EEVConfigDiagnosticLogger _Nonnull logger);
void EEVPlaybackRestrictionPolicySummary(void);
#ifdef __cplusplus
}
#endif
#endif
