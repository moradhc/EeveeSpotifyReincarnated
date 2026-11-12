#import "ProductStateDiagnostics.h"
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <execinfo.h>
#import <dlfcn.h>
#import <mach-o/loader.h>
#import <stdint.h>
#import <stdlib.h>
#import <string.h>

// Debug-only observations at the existing Objective-C/C++ boundary. A zero
// counter does not exclude direct Swift/C++ access bypassing these entries.
static EEVConfigDiagnosticLogger PSLogger;
static NSLock *PSLock;
static NSMutableDictionary<NSNumber *, NSString *> *PSLastDetails;
static NSMutableSet<NSString *> *PSImages;
static NSArray<NSString *> *PSKeys;
static const char *PSNames[] = {
    "set-original", "set-overrides", "init-dictionary", "values", "original-values",
    "map-to-dictionary", "changed-keys-to-dictionary", "string-getter",
    "subscript-getter", "ads-enabled", "cpp-bridge", "add-observer"
};
enum { PSCount = sizeof(PSNames) / sizeof(PSNames[0]) };
typedef struct {
    unsigned long long total, inputFree, outputFree, inputAds, outputAds, forced;
    unsigned int transitions;
} PSStats;
static PSStats PSCounts[PSCount];

static void PSLog(NSString *message) {
    if (PSLogger) PSLogger([[@"[STATE V4] " stringByAppendingString:message] UTF8String]);
}

static NSInteger PSIndex(const char *event) {
    for (NSUInteger i = 0; i < PSCount; i++) if (strcmp(event, PSNames[i]) == 0) return (NSInteger)i;
    return -1;
}

// Only these fixed tokens are exported. Never stringify unknown objects,
// account identifiers, dates, arbitrary product strings, or entire dictionaries.
static NSString *PSToken(id value) {
    if (!value) return @"missing";
    if ([value isKindOfClass:[NSString class]]) {
        for (NSString *allowed in @[@"free", @"premium", @"open", @"unlimited", @"trial", @"0", @"1", @"true", @"false"]) {
            if ([value isEqualToString:allowed]) return allowed;
        }
        return @"other-string";
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        if ([value isEqualToNumber:@0]) return @"0";
        if ([value isEqualToNumber:@1]) return @"1";
        return @"other-number";
    }
    return @"other-type";
}

static NSString *PSSnapshot(id dict, BOOL *freeValue, BOOL *adsValue) {
    *freeValue = NO; *adsValue = NO;
    if (![dict isKindOfClass:[NSDictionary class]]) return @"unavailable";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *key in PSKeys) {
        NSString *token = PSToken(dict[key]);
        if (([key isEqualToString:@"type"] || [key isEqualToString:@"product"] || [key isEqualToString:@"catalogue"])
            && [token isEqualToString:@"free"]) *freeValue = YES;
        if ([key isEqualToString:@"ads"] && [token isEqualToString:@"1"]) *adsValue = YES;
        [parts addObject:[NSString stringWithFormat:@"%@=%@", key, token]];
    }
    return [parts componentsJoinedByString:@","];
}

static NSString *PSImageUUID(const void *base) {
    const struct mach_header_64 *header = base;
    if (!header || header->magic != MH_MAGIC_64) return @"unavailable";
    const uint8_t *cursor = (const uint8_t *)(header + 1);
    const uint8_t *end = cursor + header->sizeofcmds;
    for (uint32_t i = 0; i < header->ncmds && cursor + sizeof(struct load_command) <= end; i++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command) || command->cmdsize > (size_t)(end - cursor)) break;
        if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
            const struct uuid_command *uuid = (const struct uuid_command *)cursor;
            return [[NSUUID alloc] initWithUUIDBytes:uuid->uuid].UUIDString;
        }
        cursor += command->cmdsize;
    }
    return @"unavailable";
}

// Offsets + image UUIDs can be matched to the supplied IPA without disclosing
// absolute device paths, ASLR addresses, stack contents, or account data.
static __attribute__((noinline)) void PSTrace(NSUInteger index, unsigned long long sequence) {
    void *frames[18];
    int count = backtrace(frames, 18);
    for (int i = 2; i < count; i++) {
        Dl_info info = {0};
        if (!dladdr(frames[i], &info) || !info.dli_fbase || !info.dli_fname) continue;
        NSString *image = [[NSString stringWithUTF8String:info.dli_fname] lastPathComponent];
        NSString *uuid = PSImageUUID(info.dli_fbase);
        NSString *identity = [NSString stringWithFormat:@"%@/%@", image, uuid];
        [PSLock lock];
        BOOL first = ![PSImages containsObject:identity];
        if (first) [PSImages addObject:identity];
        [PSLock unlock];
        if (first) PSLog([NSString stringWithFormat:@"image=%@ uuid=%@", image, uuid]);
        uintptr_t offset = (uintptr_t)frames[i] - (uintptr_t)info.dli_fbase;
        PSLog([NSString stringWithFormat:@"trace=%s n=%llu frame=%d image=%@ offset=0x%llx",
               PSNames[index], sequence, i - 2, image, (unsigned long long)offset]);
    }
}

static __attribute__((noinline)) void PSRecord(NSUInteger index, NSString *detail, BOOL inFree, BOOL outFree,
                     BOOL inAds, BOOL outAds, BOOL forced) {
    [PSLock lock];
    PSStats *stats = &PSCounts[index];
    stats->total++; stats->inputFree += inFree; stats->outputFree += outFree;
    stats->inputAds += inAds; stats->outputAds += outAds; stats->forced += forced;
    unsigned long long sequence = stats->total;
    BOOL changed = ![PSLastDetails[@(index)] isEqualToString:detail];
    // Keep late state changes visible, with a hard output budget per event.
    BOOL log = sequence <= 8 || (changed && stats->transitions < 16);
    if (changed) {
        if (stats->transitions < 16) stats->transitions++;
        PSLastDetails[@(index)] = detail;
    }
    [PSLock unlock];
    if (log) PSLog([NSString stringWithFormat:@"event=%s n=%llu %@", PSNames[index], sequence, detail]);
    if (sequence == 9) PSLog([NSString stringWithFormat:@"event=%s repeated calls counted; later changes bounded", PSNames[index]]);
    if (sequence <= 2) PSTrace(index, sequence);
}

void EEVStartProductStateDiagnostics(EEVConfigDiagnosticLogger logger) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        PSLock = [NSLock new]; PSLastDetails = [NSMutableDictionary dictionary];
        PSImages = [NSMutableSet set];
        PSKeys = @[@"type", @"product", @"catalogue", @"ads", @"on-demand", @"unrestricted",
                   @"shuffle", @"player-license", @"player-license-v2"];
        PSLogger = logger;
        PSLog(@"start; observation only; forced getter output is not server entitlement");
    });
}

void EEVProductStateDictionary(const char *event, id input, id output) {
    if (!PSLogger) return;
    NSInteger index = PSIndex(event);
    if (index < 0 || index > 6) return;
    BOOL inFree, outFree, inAds, outAds;
    NSString *before = PSSnapshot(input, &inFree, &inAds);
    NSString *after = PSSnapshot(output, &outFree, &outAds);
    PSRecord((NSUInteger)index, [NSString stringWithFormat:@"input={%@} output={%@}", before, after],
             inFree, outFree, inAds, outAds, NO);
}

void EEVProductStateGetter(const char *event, NSString *key, id value, BOOL forced) {
    if (!PSLogger) return;
    NSInteger index = PSIndex(event);
    if (index != 7 && index != 8) return;
    BOOL known = [PSKeys containsObject:key];
    NSString *token = known ? PSToken(value) : @"redacted";
    BOOL freeValue = known && ([key isEqualToString:@"type"] || [key isEqualToString:@"product"] || [key isEqualToString:@"catalogue"])
        && [token isEqualToString:@"free"];
    BOOL adsValue = known && [key isEqualToString:@"ads"] && [token isEqualToString:@"1"];
    PSRecord((NSUInteger)index, [NSString stringWithFormat:@"key=%@ output=%@ forced=%d original=%@",
             known ? key : @"other-key", token, forced, forced ? @"not-read" : @"returned"],
             NO, freeValue, NO, adsValue, forced);
}

void EEVProductStateAds(BOOL value, BOOL forced) {
    if (!PSLogger) return;
    PSRecord(9, [NSString stringWithFormat:@"output=%d forced=%d original=%@", value, forced,
                 forced ? @"not-read" : @"returned"], NO, NO, NO, value, forced);
}

static Method PSOwnMethod(Class cls, SEL selector, NSArray<NSString *> *types) {
    unsigned int count = 0;
    Method *methods = cls ? class_copyMethodList(cls, &count) : NULL;
    Method method = NULL;
    for (unsigned int i = 0; i < count; i++) {
        if (sel_isEqual(method_getName(methods[i]), selector)) { method = methods[i]; break; }
    }
    free(methods);
    if (!method || method_getNumberOfArguments(method) + 1 != types.count) return NULL;
    for (NSUInteger i = 0; i < types.count; i++) {
        char *type = i == 0 ? method_copyReturnType(method) : method_copyArgumentType(method, (unsigned int)i - 1);
        BOOL valid = type && strcmp(type, types[i].UTF8String) == 0;
        free(type);
        if (!valid) return NULL;
    }
    return method;
}

void EEVInstallProductStateBridgeProbe(void) {
    if (!PSLogger) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Verified ^v16@0:8 in 9.1.98. No attempt to interpret the C++ object.
        Class cls = NSClassFromString(@"SPTCoreProductState");
        SEL selector = NSSelectorFromString(@"cppProductState");
        Method method = PSOwnMethod(cls, selector, @[@"^v", @"@", @":"]);
        if (method) {
            void *(*original)(id, SEL) = (void *(*)(id, SEL))method_getImplementation(method);
            IMP replacement = imp_implementationWithBlock(^void *(id receiver) {
                void *value = original(receiver, selector);
                PSRecord(10, value ? @"returnedPointer=yes" : @"returnedPointer=no", NO, NO, NO, NO, NO);
                return value;
            });
            method_setImplementation(method, replacement);
            PSLog(@"probe=cpp-bridge installed");
        } else {
            PSLog(@"probe=cpp-bridge skipped (class, own method or signature unavailable)");
        }

        SEL observerSelector = NSSelectorFromString(@"addObserver:on:");
        Method observerMethod = PSOwnMethod(cls, observerSelector, @[@"v", @"@", @":", @"@", @"@"]);
        if (observerMethod) {
            void (*original)(id, SEL, id, id) = (void (*)(id, SEL, id, id))method_getImplementation(observerMethod);
            IMP replacement = imp_implementationWithBlock(^(id receiver, id observer, id scheduler) {
                const char *name = observer ? object_getClassName(observer) : "nil";
                PSRecord(11, [NSString stringWithFormat:@"observerClass=%s", name], NO, NO, NO, NO, NO);
                original(receiver, observerSelector, observer, scheduler);
            });
            method_setImplementation(observerMethod, replacement);
            PSLog(@"probe=add-observer installed");
        } else {
            PSLog(@"probe=add-observer skipped (class, own method or signature unavailable)");
        }
    });
}

void EEVProductStateSummary(void) {
    if (!PSLogger) return;
    PSStats snapshot[PSCount];
    [PSLock lock]; memcpy(snapshot, PSCounts, sizeof(snapshot)); [PSLock unlock];
    for (NSUInteger i = 0; i < PSCount; i++) {
        PSStats s = snapshot[i];
        PSLog([NSString stringWithFormat:@"summary event=%s total=%llu inputFree=%llu outputFree=%llu inputAds1=%llu outputAds1=%llu forced=%llu",
               PSNames[i], s.total, s.inputFree, s.outputFree, s.inputAds, s.outputAds, s.forced]);
    }
}
