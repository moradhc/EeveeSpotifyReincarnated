#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <stdlib.h>
#import <string.h>
#import <CommonCrypto/CommonDigest.h>
#import "PlaybackDiagnostics.h"
#import "PlaybackReasonVocabulary.h"

// Passive, ABI-checked entry points extracted from the supplied 9.1.98 IPA.
// Commands, completion blocks and return objects are forwarded unchanged.
// State callbacks additionally read a fixed set of verified model properties.
static EEVConfigDiagnosticLogger RPLogger;
static NSLock *RPLock;
static NSMutableDictionary<NSString *, NSNumber *> *RPCounts, *RPChanges;
static NSMutableDictionary<NSString *, NSString *> *RPLast;
static NSMutableDictionary<NSString *, NSValue *> *RPOriginals;
static NSSet<NSString *> *RPAllowedReasons;
static NSString *const RPUI = @"_TtC23NowPlaying_PlatformImpl28StatefulPlayerImplementation";
static NSString *const RPCore = @"SPTEsperantoPlayer";
static NSString *const RPPosition = @"_TtC23NowPlaying_PlatformImpl41StatefulPlayerTrackPositionImplementation";
static NSArray<NSString *> *RPRestrictionNames;

static void RPLog(NSString *message) {
    if (RPLogger) RPLogger([[@"[PLAYER V9] " stringByAppendingString:message] UTF8String]);
}

static unsigned long long RPRecord(NSString *event, NSString *detail) {
    [RPLock lock];
    unsigned long long count = [RPCounts[event] unsignedLongLongValue] + 1;
    RPCounts[event] = @(count);
    unsigned int changes = [RPChanges[event] unsignedIntValue];
    BOOL different = ![RPLast[event] isEqualToString:detail];
    BOOL emit = count <= 8 || (different && changes < 16);
    if (different) { RPChanges[event] = @(MIN(changes + 1, 16U)); RPLast[event] = detail; }
    [RPLock unlock];
    if (emit) RPLog([NSString stringWithFormat:@"event=%@ n=%llu %@", event, count, detail]);
    return count;
}

static Method RPOwn(Class cls, NSString *name, NSArray<NSString *> *types) {
    if (!cls) return NULL;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    Method found = NULL;
    SEL sel = NSSelectorFromString(name);
    for (unsigned int i = 0; i < count; i++) if (sel_isEqual(method_getName(methods[i]), sel)) { found = methods[i]; break; }
    free(methods);
    if (!found || method_getNumberOfArguments(found) + 1 != types.count) return NULL;
    for (NSUInteger i = 0; i < types.count; i++) {
        char *type = i == 0 ? method_copyReturnType(found) : method_copyArgumentType(found, (unsigned int)i - 1);
        BOOL equal = type && strcmp(type, types[i].UTF8String) == 0;
        if (type && [types[i] isEqualToString:@"B"] && strcmp(type, "c") == 0) equal = YES;
        free(type);
        if (!equal) return NULL;
    }
    return found;
}

static Method RPProbe(NSString *className, NSString *name, NSArray<NSString *> *types) {
    Method method = RPOwn(NSClassFromString(className), name, types);
    NSString *event = [NSString stringWithFormat:@"%@.%@", className, name];
    NSString *counter = event;
    if ([className isEqualToString:RPCore] &&
        ([name hasPrefix:@"skipTo"] || [name hasPrefix:@"executePlay"] || [name hasPrefix:@"performPlayer"] || [name isEqualToString:@"setShufflingContext:"]))
        counter = [@"core-command." stringByAppendingString:name];
    if ([className isEqualToString:RPUI] && [name hasPrefix:@"skipTo"])
        counter = [@"ui-command." stringByAppendingString:name];
    if ([className isEqualToString:RPPosition] && [name isEqualToString:@"updateWithPlayerState:eventOrigin:"])
        counter = @"position-update";
    [RPLock lock];
    RPCounts[counter] = @0;
    if (method) RPOriginals[event] = [NSValue valueWithPointer:(const void *)method_getImplementation(method)];
    [RPLock unlock];
    RPLog([NSString stringWithFormat:@"probe=%@ %@", event,
           method ? @"installed" : @"skipped (class, own method or signature unavailable)"]);
    return method;
}

static IMP RPReader(id object, NSString *className, NSString *name, NSString *returnType) {
    Class cls = NSClassFromString(className);
    if (!object || !cls || ![object isKindOfClass:cls]) return NULL;
    Method method = RPOwn(cls, name, @[returnType, @"@", @":"]);
    if (!method) return NULL;
    NSString *key = [NSString stringWithFormat:@"%@.%@", className, name];
    [RPLock lock]; IMP original = (IMP)[RPOriginals[key] pointerValue]; [RPLock unlock];
    // Bypass our own boolean probes for diagnostic reads so query counters
    // represent app calls, not the additional model-property snapshots.
    return original ?: method_getImplementation(method);
}

static id RPReadObject(id object, NSString *className, NSString *name) {
    IMP imp = RPReader(object, className, name, @"@");
    return imp ? ((id (*)(id, SEL))imp)(object, NSSelectorFromString(name)) : nil;
}

static NSString *RPUnknownReason(NSString *value, NSString *kind) {
    // Never print arbitrary reason contents. Fingerprint only short identifiers;
    // URLs, whitespace, long strings and unexpected data remain fully redacted.
    if (value.length < 2 || value.length > 80) return kind;
    NSCharacterSet *characters = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-"];
    if ([value rangeOfCharacterFromSet:characters.invertedSet].location != NSNotFound) return kind;
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:64];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return [NSString stringWithFormat:@"%@:sha256=%@", kind, hex];
}

static NSString *RPReasonToken(id item) {
    if ([item isKindOfClass:[NSString class]]) return [RPAllowedReasons containsObject:item] ? item : RPUnknownReason(item, @"unknown-string");
    Class cls = NSClassFromString(@"SPTRestrictionStatus");
    if (cls && [item isKindOfClass:cls]) {
        id value = RPReadObject(item, @"SPTRestrictionStatus", @"restrictionID");
        if (![value isKindOfClass:[NSString class]]) return @"unknown-status";
        return [RPAllowedReasons containsObject:value] ? value : RPUnknownReason(value, @"unknown-status");
    }
    return @"unknown-type";
}

static NSString *RPReasons(id value) {
    if (!value) return @"none";
    if ([value isKindOfClass:[NSString class]]) return RPReasonToken(value);
    NSArray *items = nil;
    if ([value isKindOfClass:[NSArray class]]) items = value;
    else if ([value isKindOfClass:[NSSet class]]) items = [value allObjects];
    else if ([value isKindOfClass:[NSOrderedSet class]]) items = [value array];
    if (!items) return RPReasonToken(value);
    if (!items.count) return @"none";
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (id item in items) {
        if (tokens.count == 12) { [tokens addObject:@"more"]; break; }
        [tokens addObject:RPReasonToken(item)];
    }
    return [[tokens sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","];
}

static void RPSnapshot(id state, NSString *source) {
    for (NSString *property in @[@"restrictions", @"contextRestrictions"]) {
        id restrictions = RPReadObject(state, @"SPTPlayerState", property);
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        for (NSString *name in RPRestrictionNames) {
            IMP imp = RPReader(restrictions, @"SPTPlayerRestrictions", name, @"B");
            if (!imp) continue;
            BOOL blocked = ((BOOL (*)(id, SEL))imp)(restrictions, NSSelectorFromString(name));
            NSString *reasonName = [name isEqualToString:@"disallowSwipePrevious"] ? @"disallowSwipePrevReasons" : [name stringByAppendingString:@"Reasons"];
            id reasons = RPReadObject(restrictions, @"SPTPlayerRestrictions", reasonName);
            [parts addObject:[NSString stringWithFormat:@"%@=%d[%@]", name, blocked, RPReasons(reasons)]];
        }
        RPRecord([NSString stringWithFormat:@"snapshot.%@.%@", source, property],
                 parts.count ? [parts componentsJoinedByString:@" "] : @"verified-model-unavailable");
    }
}

static void RPInstallBool(NSString *cls, NSString *name, BOOL relativeIndex) {
    Method method = RPProbe(cls, name, relativeIndex ? @[@"B", @"@", @":", @"q"] : @[@"B", @"@", @":"]);
    if (!method) return;
    SEL sel = NSSelectorFromString(name); IMP old = method_getImplementation(method);
    NSString *event = [NSString stringWithFormat:@"%@.%@", cls, name];
    IMP replacement;
    if (relativeIndex) {
        replacement = imp_implementationWithBlock(^BOOL(id self, NSInteger index) {
            BOOL value = ((BOOL (*)(id, SEL, NSInteger))old)(self, sel, index);
            RPRecord(event, [NSString stringWithFormat:@"relativeIndex=%ld blocked=%d", (long)index, value]);
            return value;
        });
    } else {
        replacement = imp_implementationWithBlock(^BOOL(id self) {
            BOOL value = ((BOOL (*)(id, SEL))old)(self, sel);
            RPRecord(event, [NSString stringWithFormat:@"blocked=%d", value]);
            return value;
        });
    }
    method_setImplementation(method, replacement);
}

static NSString *RPBoolValue(id object, NSString *cls, NSString *name) {
    IMP imp = RPReader(object, cls, name, @"B");
    if (!imp) return @"unavailable";
    return ((BOOL (*)(id, SEL))imp)(object, NSSelectorFromString(name)) ? @"1" : @"0";
}

static void RPInstallPositionUpdate(void) {
    NSString *name = @"updateWithPlayerState:eventOrigin:";
    Method method = RPProbe(RPPosition, name, @[@"v", @"@", @":", @"@", @"q"]);
    if (!method) return;
    SEL sel = NSSelectorFromString(name); IMP old = method_getImplementation(method);
    method_setImplementation(method, imp_implementationWithBlock(^(id self, id state, NSInteger origin) {
        // Preserve ordering: inspect cached flags only after the real update.
        ((void (*)(id, SEL, id, NSInteger))old)(self, sel, state, origin);
        id restrictions = RPReadObject(state, @"SPTPlayerState", @"restrictions");
        id context = RPReadObject(state, @"SPTPlayerState", @"contextRestrictions");
        NSString *detail = [NSString stringWithFormat:
            @"after-update cachedSeeking=%@ cachedSeekingAlways=%@ loading=%@ modelSeeking=%@ modelReasons=[%@] contextSeeking=%@ contextReasons=[%@]",
            RPBoolValue(self, RPPosition, @"disallowSeeking"),
            RPBoolValue(self, RPPosition, @"disallowSeekingAlways"),
            RPBoolValue(self, RPPosition, @"isLoading"),
            RPBoolValue(restrictions, @"SPTPlayerRestrictions", @"disallowSeeking"),
            RPReasons(RPReadObject(restrictions, @"SPTPlayerRestrictions", @"disallowSeekingReasons")),
            RPBoolValue(context, @"SPTPlayerRestrictions", @"disallowSeeking"),
            RPReasons(RPReadObject(context, @"SPTPlayerRestrictions", @"disallowSeekingReasons"))];
        RPRecord(@"position-update", detail);
    }));
}

static void RPInstallVoidCommand(NSString *name, BOOL withCount) {
    Method method = RPProbe(RPUI, name, withCount ? @[@"v", @"@", @":", @"q", @"B"] : @[@"v", @"@", @":"]);
    if (!method) return;
    SEL sel = NSSelectorFromString(name); IMP old = method_getImplementation(method);
    NSString *event = [@"ui-command." stringByAppendingString:name];
    IMP replacement;
    if (withCount) {
        replacement = imp_implementationWithBlock(^(id self, NSInteger count, BOOL dragging) {
            RPRecord(event, [NSString stringWithFormat:@"entered count=%ld dragging=%d", (long)count, dragging]);
            ((void (*)(id, SEL, NSInteger, BOOL))old)(self, sel, count, dragging);
        });
    } else {
        replacement = imp_implementationWithBlock(^(id self) {
            RPRecord(event, @"entered"); ((void (*)(id, SEL))old)(self, sel);
        });
    }
    method_setImplementation(method, replacement);
}

static void RPReturned(NSString *event, unsigned long long sequence, id value) {
    if (sequence <= 8) RPLog([NSString stringWithFormat:@"return=%@ n=%llu object=%d (not a completion result)", event, sequence, value != nil]);
}

static void RPInstallObjectCommand(NSString *name, NSUInteger arguments, BOOL lastIsBlock) {
    NSMutableArray<NSString *> *types = [@[@"@", @"@", @":"] mutableCopy];
    for (NSUInteger i = 0; i < arguments; i++) [types addObject:lastIsBlock && i + 1 == arguments ? @"@?" : @"@"];
    Method method = RPProbe(RPCore, name, types);
    if (!method) return;
    SEL sel = NSSelectorFromString(name); IMP old = method_getImplementation(method);
    NSString *event = [@"core-command." stringByAppendingString:name];
    IMP replacement = NULL;
    if (arguments == 1) {
        replacement = imp_implementationWithBlock(^id(id self, id a) {
            unsigned long long n = RPRecord(event, @"entered");
            id value = ((id (*)(id, SEL, id))old)(self, sel, a); RPReturned(event, n, value); return value;
        });
    } else if (arguments == 2) {
        replacement = imp_implementationWithBlock(^id(id self, id a, id b) {
            unsigned long long n = RPRecord(event, @"entered");
            id value = ((id (*)(id, SEL, id, id))old)(self, sel, a, b); RPReturned(event, n, value); return value;
        });
    } else if (arguments == 3) {
        replacement = imp_implementationWithBlock(^id(id self, id a, id b, id c) {
            unsigned long long n = RPRecord(event, @"entered");
            id value = ((id (*)(id, SEL, id, id, id))old)(self, sel, a, b, c); RPReturned(event, n, value); return value;
        });
    } else if (arguments == 4) {
        replacement = imp_implementationWithBlock(^id(id self, id a, id b, id c, id d) {
            unsigned long long n = RPRecord(event, @"entered");
            id value = ((id (*)(id, SEL, id, id, id, id))old)(self, sel, a, b, c, d); RPReturned(event, n, value); return value;
        });
    }
    if (replacement) method_setImplementation(method, replacement);
}

static void RPInstallShuffle(void) {
    NSString *name = @"setShufflingContext:";
    Method method = RPProbe(RPCore, name, @[@"@", @"@", @":", @"B"]);
    if (!method) return;
    SEL sel = NSSelectorFromString(name); IMP old = method_getImplementation(method);
    method_setImplementation(method, imp_implementationWithBlock(^id(id self, BOOL shuffle) {
        NSString *event = @"core-command.setShufflingContext:";
        unsigned long long n = RPRecord(event, [NSString stringWithFormat:@"entered enabled=%d", shuffle]);
        id value = ((id (*)(id, SEL, BOOL))old)(self, sel, shuffle); RPReturned(event, n, value); return value;
    }));
}

static void RPInstallCallback(NSString *cls, NSString *name, BOOL error) {
    Method method = RPProbe(cls, name, @[@"v", @"@", @":", @"@", @"@"]);
    if (!method) return;
    SEL sel = NSSelectorFromString(name); IMP old = method_getImplementation(method);
    NSString *event = [NSString stringWithFormat:@"%@.%@", cls, name];
    method_setImplementation(method, imp_implementationWithBlock(^(id self, id a, id b) {
        if (error) {
            if ([b isKindOfClass:[NSError class]]) {
                NSError *err = b;
                BOOL known = [@[NSURLErrorDomain, NSPOSIXErrorDomain, NSCocoaErrorDomain] containsObject:err.domain];
                RPRecord(event, [NSString stringWithFormat:@"domain=%@ code=%ld", known ? err.domain : @"other-domain", (long)err.code]);
            } else RPRecord(event, @"non-NSError");
        } else {
            RPRecord(event, @"state-callback"); RPSnapshot(b, cls);
        }
        ((void (*)(id, SEL, id, id))old)(self, sel, a, b);
    }));
}

void EEVInstallPlaybackDiagnostics(EEVConfigDiagnosticLogger logger) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        RPLock = [NSLock new]; RPCounts = [NSMutableDictionary dictionary]; RPChanges = [NSMutableDictionary dictionary];
        RPLast = [NSMutableDictionary dictionary]; RPOriginals = [NSMutableDictionary dictionary]; RPLogger = logger;
        RPAllowedReasons = [NSSet setWithArray:@[@"mft_disallow", @"mft_plus_disallow", @"mftplus_pick_and_shuffle_capped",
            @"premium_required", @"restrictions_skip_limit", @"restrictions_repeat_limit", @"no_prev_track", @"ad_disallow",
            @"already_paused", @"not_paused", @"already_set", @"disallowed_by_user_setting", @"video_unavailable_offline",
            @"narration", @"audiobook_capping", @"not_available_in_non_premium", @"not_available_offline",
            @"not_supported_by_device", @"not_supported_by_content_type", @"client_restriction", @"client_offline",
            @"context_restrictions", @"restrictions_permissions", @"not_available", @"disallowed", @"unknown"]];
        RPAllowedReasons = [RPAllowedReasons setByAddingObjectsFromArray:EEVPlaybackReasonVocabularyV9()];
        RPRestrictionNames = @[@"disallowSkippingToPreviousTrack", @"disallowSkippingToNextTrack", @"disallowTogglingShuffle",
            @"disallowSeeking", @"disallowUpdatingContext", @"disallowInterruptingPlayback", @"disallowSwipePrevious",
            @"disallowSwipeNext", @"disallowTapToPlayTrackInNextTracks"];
        RPLog(@"install begin; observation only; fixed model-property snapshots enabled");
        for (NSString *name in RPRestrictionNames) RPInstallBool(@"SPTPlayerRestrictions", name, NO);
        RPInstallBool(RPUI, @"disallowSkippingToRelativeIndex:", YES);
        RPInstallBool(RPUI, @"disallowSeeking", NO);
        RPInstallVoidCommand(@"skipToPreviousTrack", NO); RPInstallVoidCommand(@"skipToNextTrack", NO);
        RPInstallVoidCommand(@"skipToPreviousTrackTimes:whileDragging:", YES);
        RPInstallVoidCommand(@"skipToNextTrackTimes:whileDragging:", YES);
        for (NSString *direction in @[@"Previous", @"Next"]) {
            RPInstallObjectCommand([NSString stringWithFormat:@"skipTo%@TrackWithOptions:", direction], 1, NO);
            RPInstallObjectCommand([NSString stringWithFormat:@"skipTo%@TrackWithOptions:track:", direction], 2, NO);
            RPInstallObjectCommand([NSString stringWithFormat:@"skipTo%@TrackWithOptions:track:loggingParams:", direction], 3, NO);
        }
        RPInstallObjectCommand(@"executePlayCommand:options:loggingParams:origin:", 4, NO);
        RPInstallObjectCommand(@"performPlayerCommandWithOptions:command:", 2, YES);
        RPInstallShuffle();
        RPInstallCallback(RPCore, @"globalPlayerSubscription:gotStateUpdate:", NO);
        RPInstallCallback(RPUI, @"player:stateDidChange:", NO);
        RPInstallCallback(RPUI, @"player:didEncounterError:", YES);
        RPInstallPositionUpdate();
        RPLog(@"install complete");
    });
}

void EEVPlaybackDiagnosticsSummary(void) {
    if (!RPLogger) return;
    [RPLock lock]; NSDictionary *counts = [RPCounts copy]; [RPLock unlock];
    for (NSString *key in [[counts allKeys] sortedArrayUsingSelector:@selector(compare:)])
        RPLog([NSString stringWithFormat:@"summary event=%@ total=%@", key, counts[key]]);
}
