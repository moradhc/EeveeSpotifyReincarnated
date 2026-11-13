#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <stdlib.h>
#import <string.h>
#import "PlaybackRestrictionPolicy.h"

// V8 is a local model experiment for the supplied 9.1.98 build. It does not
// change the C++ player state, account entitlement or command results.
// Only the reason/property pairs observed in debug (13) are eligible.
static EEVPlaybackPolicyEnabled PREnabled;
static EEVConfigDiagnosticLogger PRLogger;
static NSLock *PRLock;
static NSMutableDictionary<NSString *, NSNumber *> *PRCounts;
static IMP PRStatusID;
static Class PRStatusClass;

static void PRLog(NSString *text) {
    if (PRLogger) PRLogger([[@"[RESTRICT V8] " stringByAppendingString:text] UTF8String]);
}

static Method PROwn(Class cls, NSString *name, const char *returnType) {
    if (!cls) return NULL;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count), found = NULL;
    SEL sel = NSSelectorFromString(name);
    for (unsigned int i = 0; i < count; i++) {
        if (sel_isEqual(method_getName(methods[i]), sel)) { found = methods[i]; break; }
    }
    free(methods);
    if (!found || method_getNumberOfArguments(found) != 2) return NULL;
    const char *expected[] = { returnType, "@", ":" };
    for (unsigned int i = 0; i < 3; i++) {
        char *actual = i == 0 ? method_copyReturnType(found) : method_copyArgumentType(found, i - 1);
        BOOL ok = actual && (!strcmp(actual, expected[i]) ||
            (i == 0 && !strcmp(returnType, "B") && !strcmp(actual, "c")));
        free(actual);
        if (!ok) return NULL;
    }
    return found;
}

static BOOL PRMatches(id item, NSSet<NSString *> *allowed) {
    id token = item;
    if (PRStatusID && [item isKindOfClass:PRStatusClass]) {
        token = ((id (*)(id, SEL))PRStatusID)(item, NSSelectorFromString(@"restrictionID"));
    }
    return [token isKindOfClass:[NSString class]] && [allowed containsObject:token];
}

// Preserve the collection family, element identity/order, unknown reasons and
// the original object when unchanged. Never mutate Spotify's input collections.
static id PRFilter(id input, NSSet<NSString *> *allowed, NSUInteger *removed, NSUInteger *remaining) {
    *removed = 0; *remaining = 0;
    NSArray *items;
    if ([input isKindOfClass:[NSArray class]]) items = input;
    else if ([input isKindOfClass:[NSSet class]]) items = [input allObjects];
    else if ([input isKindOfClass:[NSOrderedSet class]]) items = [input array];
    else return input; // Unverified scalar/nil/container: leave it alone.
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:items.count];
    for (id item in items) {
        if (PRMatches(item, allowed)) (*removed)++;
        else [kept addObject:item];
    }
    *remaining = kept.count;
    if (!*removed) return input;
    if ([input isKindOfClass:[NSSet class]]) return [NSSet setWithArray:kept];
    if ([input isKindOfClass:[NSOrderedSet class]]) return [NSOrderedSet orderedSetWithArray:kept];
    return [kept copy];
}

static void PRRecord(NSString *event, NSString *detail) {
    [PRLock lock];
    unsigned long long n = [PRCounts[event] unsignedLongLongValue] + 1;
    PRCounts[event] = @(n);
    [PRLock unlock];
    if (n <= 8) PRLog([NSString stringWithFormat:@"event=%@ n=%llu %@", event, n, detail]);
}

void EEVInstallPlaybackRestrictionPolicy(const char *version,
    EEVPlaybackPolicyEnabled enabled, EEVConfigDiagnosticLogger logger) {
    if (strcmp(version, "9.1.98")) {
        logger("[RESTRICT V8] skipped: unsupported-version"); return;
    }
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        PREnabled = enabled; PRLogger = logger;
        PRLock = [NSLock new]; PRCounts = [NSMutableDictionary dictionary];
        PRStatusClass = NSClassFromString(@"SPTRestrictionStatus");
        Method status = PROwn(PRStatusClass, @"restrictionID", "@");
        PRStatusID = status ? method_getImplementation(status) : NULL;
        NSDictionary<NSString *, NSArray<NSString *> *> *rules = @{
            @"disallowSkippingToPreviousTrack": @[@"mft_disallow", @"ad_disallow"],
            @"disallowSkippingToNextTrack": @[@"ad_disallow"],
            @"disallowTogglingShuffle": @[@"mft_disallow"],
            @"disallowSeeking": @[@"mft_disallow", @"ad_disallow"],
            @"disallowInterruptingPlayback": @[@"ad_disallow"]
        };
        Class cls = NSClassFromString(@"SPTPlayerRestrictions");
        PRLog(@"install begin; local-model policy; no core entitlement change");
        NSUInteger installed = 0;
        for (NSString *name in [[rules allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            NSString *reasonName = [name stringByAppendingString:@"Reasons"];
            Method boolMethod = PROwn(cls, name, "B");
            Method reasonsMethod = PROwn(cls, reasonName, "@");
            if (!boolMethod || !reasonsMethod) {
                PRLog([NSString stringWithFormat:@"pair=%@ skipped (class, own method or ABI unavailable)", name]);
                continue;
            }
            IMP oldBool = method_getImplementation(boolMethod);
            IMP oldReasons = method_getImplementation(reasonsMethod);
            SEL boolSel = NSSelectorFromString(name), reasonSel = NSSelectorFromString(reasonName);
            NSSet *allowed = [NSSet setWithArray:rules[name]];
            method_setImplementation(reasonsMethod, imp_implementationWithBlock(^id(id self) {
                id raw = ((id (*)(id, SEL))oldReasons)(self, reasonSel);
                if (!PREnabled()) return raw;
                NSUInteger removed, remaining;
                id output = PRFilter(raw, allowed, &removed, &remaining);
                if (removed) PRRecord(reasonName, [NSString stringWithFormat:@"removed=%lu remaining=%lu", (unsigned long)removed, (unsigned long)remaining]);
                return output;
            }));
            method_setImplementation(boolMethod, imp_implementationWithBlock(^BOOL(id self) {
                BOOL original = ((BOOL (*)(id, SEL))oldBool)(self, boolSel);
                if (!PREnabled()) return original;
                // Read the captured original getter, not our filtered view.
                id raw = ((id (*)(id, SEL))oldReasons)(self, reasonSel);
                NSUInteger removed, remaining;
                PRFilter(raw, allowed, &removed, &remaining);
                BOOL output = removed > 0 && remaining == 0 ? NO : original;
                if (removed) PRRecord(name, [NSString stringWithFormat:@"removed=%lu remaining=%lu blocked=%d", (unsigned long)removed, (unsigned long)remaining, output]);
                return output;
            }));
            installed++;
            PRLog([NSString stringWithFormat:@"pair=%@ installed", name]);
        }
        PRLog([NSString stringWithFormat:@"install complete; pairs=%lu/5 enabled=%d", (unsigned long)installed, PREnabled()]);
    });
}

void EEVPlaybackRestrictionPolicySummary(void) {
    [PRLock lock]; NSDictionary *counts = [PRCounts copy]; [PRLock unlock];
    for (NSString *event in [[counts allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        PRLog([NSString stringWithFormat:@"summary event=%@ filtered=%@", event, counts[event]]);
    }
}
