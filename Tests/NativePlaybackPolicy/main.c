#include <assert.h>
#include <stdio.h>
#include "NativePlaybackPolicy.h"
int main(void) {
    const uintptr_t expected = 0x1039d5bb8;
    for (uint32_t state = 0; state < 256; state++) {
        assert(EEVNativePlaybackShouldOverride(true, expected, expected, state) ==
            (state == 3 || state == 4));
        assert(!EEVNativePlaybackShouldOverride(false, expected, expected, state));
        assert(!EEVNativePlaybackShouldOverride(true, expected + 4, expected, state));
        assert(!EEVNativePlaybackShouldOverride(true, expected - 4, expected, state));
        assert(!EEVNativePlaybackShouldOverride(true, 0, 0, state));
    }
    assert(!EEVNativePlaybackShouldOverride(true, expected, expected, UINT32_MAX));
    puts("NativePlaybackPolicy: PASS");
}
