#import "NativePlaybackFix.h"
#import "NativePlaybackPolicy.h"
#include <dispatch/dispatch.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach/vm_prot.h>
#include <dlfcn.h>
#include <stdatomic.h>
#include <string.h>

// Spotify 9.2.0 (920002054), UUID b49e7578-1d86-35d3-8bb5-7daf68fed8a8.
// Mirrors the scoped Frida experiment confirmed on the user's device:
// previous-track and seeking work; selecting an exact song still does not.
// No broader entitlement / shuffle / UI changes are implied.
static EEVNativePlaybackEnabled NPEnabled;
static EEVConfigDiagnosticLogger NPLogger;
static uintptr_t NPCaller;
static const uint32_t NPPremium = 0;
static atomic_uint NPHits;

__attribute__((noinline))
static const uint32_t *NPGetState(void *object) {
    uintptr_t caller = (uintptr_t)__builtin_extract_return_addr(__builtin_return_address(0));
    // The UUID and all eight original bytes are checked before installing.
    // Original getter is exactly: add x0, x0, #12; ret.
    const uint32_t *original = (const uint32_t *)((const char *)object + 12);
    if (caller != NPCaller || !NPEnabled || !NPEnabled()) return original;
    if (!EEVNativePlaybackShouldOverride(true, caller, NPCaller, *original)) return original;
    unsigned int hit = atomic_fetch_add_explicit(&NPHits, 1, memory_order_relaxed);
    if (hit < 3 && NPLogger) NPLogger("[CORE V11] applied restriction-state 3/4 -> 0");
    return &NPPremium;
}

static bool NPExecutable(const struct mach_header_64 *header, intptr_t slide,
    uintptr_t address, size_t length) {
    const uint8_t *p = (const uint8_t *)(header + 1);
    const uint8_t *end = p + header->sizeofcmds;
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if ((size_t)(end - p) < sizeof(struct load_command)) return false;
        const struct load_command *lc = (const void *)p;
        if (lc->cmdsize < sizeof(*lc) || lc->cmdsize > (size_t)(end - p)) return false;
        if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg = (const void *)lc;
            uintptr_t start = (uintptr_t)(seg->vmaddr + slide);
            if ((seg->initprot & (VM_PROT_READ | VM_PROT_EXECUTE)) == (VM_PROT_READ | VM_PROT_EXECUTE) &&
                address >= start && address - start <= seg->vmsize &&
                length <= seg->vmsize - (address - start)) return true;
        }
        p += lc->cmdsize;
    }
    return false;
}

void EEVInstallNativePlaybackFix(EEVNativePlaybackEnabled enabled, EEVConfigDiagnosticLogger logger) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
#if defined(__aarch64__)
        const struct mach_header_64 *header = (const void *)_dyld_get_image_header(0);
        if (!header || header->magic != MH_MAGIC_64 || header->filetype != MH_EXECUTE) {
            logger("[CORE V11] skipped: main image unavailable"); return;
        }
        const uint8_t expectedUUID[16] = {0xb4,0x9e,0x75,0x78,0x1d,0x86,0x35,0xd3,
            0x8b,0xb5,0x7d,0xaf,0x68,0xfe,0xd8,0xa8};
        bool matchingUUID = false;
        const uint8_t *p = (const uint8_t *)(header + 1), *end = p + header->sizeofcmds;
        for (uint32_t i = 0; i < header->ncmds; i++) {
            if ((size_t)(end - p) < sizeof(struct load_command)) break;
            const struct load_command *lc = (const void *)p;
            if (lc->cmdsize < sizeof(*lc) || lc->cmdsize > (size_t)(end - p)) break;
            if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command))
                matchingUUID = !memcmp(((const struct uuid_command *)lc)->uuid, expectedUUID, 16);
            p += lc->cmdsize;
        }
        if (!matchingUUID) { logger("[CORE V11] skipped: unsupported UUID"); return; }
        uintptr_t target = (uintptr_t)header + 0x5db6994;
        uintptr_t caller = (uintptr_t)header + 0x39d5bb8;
        intptr_t slide = _dyld_get_image_vmaddr_slide(0);
        const uint8_t getterBytes[8] = {0x00,0x30,0x00,0x91,0xc0,0x03,0x5f,0xd6};
        const uint8_t callerBytes[8] = {0x08,0x00,0x40,0xb9,0x1f,0x15,0x00,0x71};
        if (!NPExecutable(header, slide, target, 8) || !NPExecutable(header, slide, caller, 8) ||
            memcmp((const void *)target, getterBytes, 8) || memcmp((const void *)caller, callerBytes, 8)) {
            logger("[CORE V11] skipped: code mismatch or existing hook"); return;
        }
        typedef void (*HookFunction)(void *, void *, void **);
        HookFunction hook = (HookFunction)dlsym(RTLD_DEFAULT, "MSHookFunction");
        if (!hook) { logger("[CORE V11] skipped: MSHookFunction unavailable"); return; }
        NPEnabled = enabled; NPLogger = logger; NPCaller = caller;
        // No trampoline is required: NPGetState reproduces the verified getter
        // for every other caller and while patching is disabled.
        hook((void *)target, (void *)&NPGetState, NULL);
        // The backend API has no status return. Only 'applied' proves execution.
        logger("[CORE V11] hook requested; wait for applied; scope=restriction-builder");
#else
        logger("[CORE V11] skipped: unsupported architecture");
#endif
    });
}
