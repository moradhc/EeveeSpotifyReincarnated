#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <stdlib.h>
#import <string.h>
#import "PlaybackRestrictionPolicy.h"
#import "PlaybackDiagnostics.h"

static BOOL active = YES, independentBlock;
static id reasons;
static unsigned int originalBoolCalls;
static NSMutableArray<NSString *> *logs;
static void check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"FAIL: %@", message); abort(); } }
static bool enabled(void) { return active; }
static void logger(const char *message) { [logs addObject:[NSString stringWithUTF8String:message]]; }
static id getReasons(id self, SEL sel) { (void)self; (void)sel; return reasons; }
static id statusID(id self, SEL sel) { (void)sel; return objc_getAssociatedObject(self, @selector(description)); }
static BOOL getBool(id self, SEL sel) {
    originalBoolCalls++;
    if (independentBlock) return YES;
    SEL getter = NSSelectorFromString([NSStringFromSelector(sel) stringByAppendingString:@"Reasons"]);
    IMP imp = [self methodForSelector:getter];
    id value = ((id (*)(id, SEL))imp)(self, getter);
    return [value respondsToSelector:@selector(count)] ? [value count] > 0 : YES;
}
static void add(Class cls, NSString *name, IMP imp, const char *encoding) {
    check(class_addMethod(cls, NSSelectorFromString(name), imp, encoding), @"fixture registration");
}
static BOOL blocked(id object, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    return ((BOOL (*)(id, SEL))[object methodForSelector:sel])(object, sel);
}
static id readReasons(id object, NSString *name) {
    SEL sel = NSSelectorFromString([name stringByAppendingString:@"Reasons"]);
    return ((id (*)(id, SEL))[object methodForSelector:sel])(object, sel);
}
static BOOL logged(NSString *part) {
    for (NSString *line in logs) if ([line containsString:part]) return YES;
    return NO;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        logs = [NSMutableArray array];
        NSString *mode = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"normal";
        BOOL mismatch = [mode isEqualToString:@"mismatch"];
        BOOL inherited = [mode isEqualToString:@"inherited"];
        NSArray *names = @[@"disallowSkippingToPreviousTrack", @"disallowSkippingToNextTrack",
            @"disallowTogglingShuffle", @"disallowSeeking", @"disallowInterruptingPlayback"];
        Class parent = [NSObject class];
        if (inherited) {
            parent = objc_allocateClassPair(parent, "RestrictionParent", 0);
            add(parent, names[0], (IMP)getBool, "B16@0:8");
            objc_registerClassPair(parent);
        }
        Class cls = objc_allocateClassPair(parent, "SPTPlayerRestrictions", 0);
        for (NSString *name in names) {
            if (!(inherited && [name isEqual:names[0]]))
                add(cls, name, (IMP)getBool, mismatch ? "q16@0:8" : "B16@0:8");
            add(cls, [name stringByAppendingString:@"Reasons"], (IMP)getReasons, "@16@0:8");
        }
        // An unrelated restriction must remain untouched.
        add(cls, @"disallowUpdatingContext", (IMP)getBool, "B16@0:8");
        add(cls, @"disallowUpdatingContextReasons", (IMP)getReasons, "@16@0:8");
        objc_registerClassPair(cls); id object = [[cls alloc] init];
        Class statusClass = objc_allocateClassPair([NSObject class], "SPTRestrictionStatus", 0);
        add(statusClass, @"restrictionID", (IMP)statusID, "@16@0:8");
        objc_registerClassPair(statusClass);
        id status = [[statusClass alloc] init];
        objc_setAssociatedObject(status, @selector(description), @"mft_disallow", OBJC_ASSOCIATION_COPY_NONATOMIC);
        reasons = @[@"mft_disallow"];
        BOOL unsupported = [mode isEqualToString:@"unsupported"];
        EEVInstallPlaybackRestrictionPolicy(unsupported ? "9.1.90" : "9.1.98", enabled, logger);
        if (unsupported || mismatch || inherited) {
            check(readReasons(object, names[0]) == reasons, @"incompatible pair must stay intact");
            check(logged(@"skipped"), @"skip is visible");
            NSLog(@"PASS PlaybackRestrictionPolicy %@", mode); return 0;
        }
        EEVInstallPlaybackRestrictionPolicy("9.1.98", enabled, logger);
        if ([mode isEqualToString:@"with-v7"]) EEVInstallPlaybackDiagnostics(logger);
        check(!blocked(object, names[0]), @"observed mft previous restriction removed");
        check(originalBoolCalls == 1, @"original bool called once; repeat install is idempotent");
        check([readReasons(object, names[0]) count] == 0, @"reason and boolean agree");
        check([reasons count] == 1, @"input not mutated");
        check(blocked(object, names[1]), @"unobserved mft on next preserved");
        check(blocked(object, @"disallowUpdatingContext"), @"unrelated restriction preserved");
        for (NSString *name in @[names[0], names[2], names[3]])
            check(!blocked(object, name), @"observed mft properties unblocked");
        reasons = @[@"ad_disallow"];
        for (NSString *name in @[names[0], names[1], names[3], names[4]])
            check(!blocked(object, name), @"observed ad properties unblocked");
        check(blocked(object, names[2]), @"unobserved ad shuffle reason preserved");
        id unknown = [NSObject new];
        reasons = @[@"mft_disallow", @"no_prev_track", unknown, @"PRIVATE_REASON"];
        NSArray *filtered = readReasons(object, names[0]);
        check([filtered isEqual:@[@"no_prev_track", unknown, @"PRIVATE_REASON"]], @"mixed reasons retain identity and order");
        check(blocked(object, names[0]), @"remaining reasons keep control blocked");
        reasons = @[@"restrictions_skip_limit"];
        check(readReasons(object, names[1]) == reasons && blocked(object, names[1]), @"skip limit preserved");
        reasons = @[status];
        check(!blocked(object, names[0]), @"verified restriction-status model supported");
        objc_setAssociatedObject(status, @selector(description), @"PRIVATE_REASON", OBJC_ASSOCIATION_COPY_NONATOMIC);
        check(readReasons(object, names[0]) == reasons, @"unknown status preserved");
        reasons = [NSSet setWithArray:@[@"mft_disallow", @"no_prev_track"]];
        check([readReasons(object, names[0]) isEqual:[NSSet setWithObject:@"no_prev_track"]], @"set preserved");
        reasons = [NSOrderedSet orderedSetWithArray:@[@"mft_disallow", @"no_prev_track"]];
        check([readReasons(object, names[0]) isEqual:[NSOrderedSet orderedSetWithObject:@"no_prev_track"]], @"ordered set preserved");
        for (id scalar in @[@"mft_disallow", @42, @{@"reason": @"mft_disallow"}, [NSNull null]]) {
            reasons = scalar;
            check(readReasons(object, names[0]) == scalar && blocked(object, names[0]), @"unverified type preserved");
        }
        reasons = nil; check(readReasons(object, names[0]) == nil && blocked(object, names[0]), @"nil does not clear independent restriction");
        independentBlock = YES; reasons = @[];
        check(blocked(object, names[0]), @"empty reasons do not override original block");
        reasons = @[@"mft_disallow"];
        check(!blocked(object, names[0]), @"bool fallback supports stored native flag");
        active = NO;
        check(readReasons(object, names[0]) == reasons && blocked(object, names[0]), @"disable restores original behavior immediately");
        EEVPlaybackRestrictionPolicySummary();
        check(logged(@"pairs=5/5") && logged(@"remaining=1") && logged(@"summary event="), @"bounded diagnostic evidence");
        check(!logged(@"PRIVATE_REASON"), @"reason contents never logged");
        NSLog(@"PASS PlaybackRestrictionPolicy %@", mode);
    }
    return 0;
}
