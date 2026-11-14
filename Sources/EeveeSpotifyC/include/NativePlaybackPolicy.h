#ifndef EEV_NATIVE_PLAYBACK_POLICY_H
#define EEV_NATIVE_PLAYBACK_POLICY_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

// Restriction-builder caller only. Other license consumers stay unchanged.
static inline bool EEVNativePlaybackShouldOverride(bool enabled, uintptr_t caller,
    uintptr_t expectedCaller, uint32_t state) {
    return enabled && expectedCaller != 0 && caller == expectedCaller &&
        (state == 3 || state == 4);
}
#endif
