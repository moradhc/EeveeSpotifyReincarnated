#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import "PlaybackDiagnostics.h"

static NSMutableArray<NSString *> *logs;
static id core, ui, state, restriction, status, a, b, c, d, result, callback;
static NSArray *reasons;
static NSError *expectedError;
static unsigned int commandCalls[7], callbackCalls, voidCalls, boolCalls;
static void require(BOOL value, NSString *message) { if (!value) { NSLog(@"FAIL: %@", message); abort(); } }
static void logger(const char *line) { [logs addObject:[NSString stringWithUTF8String:line]]; }
static BOOL logged(NSString *part) { for (NSString *line in logs) if ([line containsString:part]) return YES; return NO; }
static BOOL blocked(id self, SEL cmd) { (void)cmd; require(self == restriction, @"restriction receiver changed"); boolCalls++; return YES; }
static id getReasons(id self, SEL cmd) { (void)cmd; require(self == restriction, @"reasons receiver changed"); return reasons; }
static id getRestriction(id self, SEL cmd) { (void)cmd; require(self == state, @"state receiver changed"); return restriction; }
static id getID(id self, SEL cmd) { (void)cmd; require(self == status, @"status receiver changed"); return @"mft_disallow"; }
static BOOL relative(id self, SEL cmd, NSInteger index) { (void)cmd; require(self == ui && index == -1, @"relative index changed"); return YES; }
static void voidCommand(id self, SEL cmd) { (void)cmd; require(self == ui, @"UI receiver changed"); voidCalls++; }
static void countedCommand(id self, SEL cmd, NSInteger count, BOOL dragging) {
    (void)cmd; require(self == ui && count == 5 && !dragging, @"UI command arguments changed"); voidCalls++;
}
static id object1(id self, SEL cmd, id x) { (void)cmd; require(self == core && x == a, @"one argument changed"); commandCalls[0]++; return result; }
static id object2(id self, SEL cmd, id x, id y) { (void)cmd; require(self == core && x == a && y == b, @"two arguments changed"); commandCalls[1]++; return result; }
static id object3(id self, SEL cmd, id x, id y, id z) { (void)cmd; require(self == core && x == a && y == b && z == c, @"three arguments changed"); commandCalls[2]++; return result; }
static id object4(id self, SEL cmd, id x, id y, id z, id w) { (void)cmd; require(self == core && x == a && y == b && z == c && w == d, @"four arguments changed"); commandCalls[3]++; return result; }
static id objectBlock(id self, SEL cmd, id x, id block) {
    (void)cmd; require(self == core && x == a && block == callback, @"block identity changed");
    commandCalls[4]++; ((void (^)(void))block)(); return result;
}
static id shuffle(id self, SEL cmd, BOOL enabled) { (void)cmd; require(self == core && enabled, @"shuffle argument changed"); commandCalls[5]++; return result; }
static void stateCallback(id self, SEL cmd, id first, id second) {
    (void)cmd; require((self == core || self == ui) && first == a && second == state, @"state callback arguments changed"); callbackCalls++;
}
static void errorCallback(id self, SEL cmd, id first, id second) {
    (void)cmd; require(self == ui && first == a && second == expectedError, @"error callback changed"); callbackCalls++;
}
static void add(Class cls, NSString *name, IMP imp, const char *types) {
    require(class_addMethod(cls, NSSelectorFromString(name), imp, types), @"fixture method not added");
}
static IMP imp(id object, NSString *name) { return method_getImplementation(class_getInstanceMethod(object_getClass(object), NSSelectorFromString(name))); }

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        logs = [NSMutableArray array];
        BOOL mismatch = argc > 1 && strcmp(argv[1], "mismatch") == 0;
        BOOL inherited = argc > 1 && strcmp(argv[1], "inherited") == 0;
        Class parent = [NSObject class];
        if (inherited) {
            parent = objc_allocateClassPair(parent, "RPRestrictionParent", 0);
            add(parent, @"disallowSkippingToPreviousTrack", (IMP)blocked, "B16@0:8");
            objc_registerClassPair(parent);
        }
        Class rc = objc_allocateClassPair(parent, "SPTPlayerRestrictions", 0);
        if (!inherited) add(rc, @"disallowSkippingToPreviousTrack", (IMP)blocked, mismatch ? "q16@0:8" : "B16@0:8");
        add(rc, @"disallowSkippingToPreviousTrackReasons", (IMP)getReasons, "@16@0:8");
        objc_registerClassPair(rc); restriction = [[rc alloc] init];
        Class sc = objc_allocateClassPair([NSObject class], "SPTPlayerState", 0);
        add(sc, @"restrictions", (IMP)getRestriction, "@16@0:8");
        add(sc, @"contextRestrictions", (IMP)getRestriction, "@16@0:8");
        objc_registerClassPair(sc); state = [[sc alloc] init];
        Class statusClass = objc_allocateClassPair([NSObject class], "SPTRestrictionStatus", 0);
        add(statusClass, @"restrictionID", (IMP)getID, "@16@0:8");
        objc_registerClassPair(statusClass); status = [[statusClass alloc] init];
        reasons = @[status, @"PRIVATE_REASON", [NSNull null]];

        Class cc = objc_allocateClassPair([NSObject class], "SPTEsperantoPlayer", 0);
        add(cc, @"skipToPreviousTrackWithOptions:", (IMP)object1, "@24@0:8@16");
        add(cc, @"skipToPreviousTrackWithOptions:track:", (IMP)object2, "@32@0:8@16@24");
        add(cc, @"skipToNextTrackWithOptions:track:loggingParams:", (IMP)object3, "@40@0:8@16@24@32");
        add(cc, @"executePlayCommand:options:loggingParams:origin:", (IMP)object4, "@48@0:8@16@24@32@40");
        add(cc, @"performPlayerCommandWithOptions:command:", (IMP)objectBlock, "@32@0:8@16@?24");
        add(cc, @"setShufflingContext:", (IMP)shuffle, "@20@0:8B16");
        add(cc, @"globalPlayerSubscription:gotStateUpdate:", (IMP)stateCallback, "v32@0:8@16@24");
        objc_registerClassPair(cc); core = [[cc alloc] init];
        Class uc = objc_allocateClassPair([NSObject class], "_TtC23NowPlaying_PlatformImpl28StatefulPlayerImplementation", 0);
        add(uc, @"skipToPreviousTrack", (IMP)voidCommand, "v16@0:8");
        add(uc, @"skipToNextTrackTimes:whileDragging:", (IMP)countedCommand, "v28@0:8q16B24");
        add(uc, @"disallowSkippingToRelativeIndex:", (IMP)relative, "B24@0:8q16");
        add(uc, @"player:stateDidChange:", (IMP)stateCallback, "v32@0:8@16@24");
        add(uc, @"player:didEncounterError:", (IMP)errorCallback, "v32@0:8@16@24");
        objc_registerClassPair(uc); ui = [[uc alloc] init];
        a = @"PRIVATE_ARGUMENT"; b = [NSObject new]; c = [NSObject new]; d = [NSObject new]; result = [NSObject new];
        __block unsigned int completions = 0;
        callback = [^{ completions++; } copy];
        EEVPlaybackDiagnosticsSummary(); require(logs.count == 0, @"logging active before install");
        EEVInstallPlaybackDiagnostics(logger);
        IMP first = imp(core, @"skipToPreviousTrackWithOptions:");
        EEVInstallPlaybackDiagnostics(logger);
        require(imp(core, @"skipToPreviousTrackWithOptions:") == first && commandCalls[0] == 0, @"duplicate install or command invoked during install");
        if (mismatch || inherited) {
            require(imp(restriction, @"disallowSkippingToPreviousTrack") == (IMP)blocked, @"invalid/inherited ABI was changed");
            require(logged(@"probe=SPTPlayerRestrictions.disallowSkippingToPreviousTrack skipped"), @"skip not reported");
            puts("Playback diagnostics: invalid/inherited method skipped"); return 0;
        }

        for (int i = 0; i < 20; i++) require(((id (*)(id, SEL, id))first)(core, NSSelectorFromString(@"skipToPreviousTrackWithOptions:"), a) == result, @"return identity changed");
        NSString *name = @"skipToPreviousTrackWithOptions:track:";
        require(((id (*)(id, SEL, id, id))imp(core, name))(core, NSSelectorFromString(name), a, b) == result, @"arity2 return changed");
        name = @"skipToNextTrackWithOptions:track:loggingParams:";
        require(((id (*)(id, SEL, id, id, id))imp(core, name))(core, NSSelectorFromString(name), a, b, c) == result, @"arity3 return changed");
        name = @"executePlayCommand:options:loggingParams:origin:";
        require(((id (*)(id, SEL, id, id, id, id))imp(core, name))(core, NSSelectorFromString(name), a, b, c, d) == result, @"arity4 return changed");
        name = @"performPlayerCommandWithOptions:command:";
        require(((id (*)(id, SEL, id, id))imp(core, name))(core, NSSelectorFromString(name), a, callback) == result && completions == 1, @"command block altered");
        name = @"setShufflingContext:";
        require(((id (*)(id, SEL, BOOL))imp(core, name))(core, NSSelectorFromString(name), YES) == result, @"shuffle return changed");
        name = @"skipToPreviousTrack";
        ((void (*)(id, SEL))imp(ui, name))(ui, NSSelectorFromString(name));
        name = @"skipToNextTrackTimes:whileDragging:";
        ((void (*)(id, SEL, NSInteger, BOOL))imp(ui, name))(ui, NSSelectorFromString(name), 5, NO);
        name = @"disallowSkippingToRelativeIndex:";
        require(((BOOL (*)(id, SEL, NSInteger))imp(ui, name))(ui, NSSelectorFromString(name), -1), @"relative restriction changed");
        name = @"disallowSkippingToPreviousTrack";
        require(((BOOL (*)(id, SEL))imp(restriction, name))(restriction, NSSelectorFromString(name)), @"restriction changed");
        name = @"globalPlayerSubscription:gotStateUpdate:";
        ((void (*)(id, SEL, id, id))imp(core, name))(core, NSSelectorFromString(name), a, state);
        name = @"player:stateDidChange:";
        ((void (*)(id, SEL, id, id))imp(ui, name))(ui, NSSelectorFromString(name), a, state);
        expectedError = [NSError errorWithDomain:NSURLErrorDomain code:-1009 userInfo:@{NSLocalizedDescriptionKey: @"PRIVATE_ERROR"}];
        name = @"player:didEncounterError:";
        ((void (*)(id, SEL, id, id))imp(ui, name))(ui, NSSelectorFromString(name), a, expectedError);
        EEVPlaybackDiagnosticsSummary();
        require(callbackCalls == 3 && voidCalls == 2 && commandCalls[0] == 20, @"original invocation count changed");
        for (int i = 1; i <= 5; i++) require(commandCalls[i] == 1, @"object command called more than once");
        require(boolCalls == 5, @"expected one app read plus four model snapshots");
        require(logged(@"summary event=SPTPlayerRestrictions.disallowSkippingToPreviousTrack total=1"), @"diagnostic reads counted as app calls");
        require(logged(@"summary event=core-command.skipToPreviousTrackWithOptions: total=20"), @"throttled calls lost");
        require(logged(@"disallowSkippingToPreviousTrack=1[mft_disallow,unknown-string,unknown-type]"), @"restriction snapshot missing/redaction wrong");
        require(logged(@"code=-1009") && logged(@"not a completion result"), @"error/return distinction missing");
        require(!logged(@"PRIVATE_"), @"private argument/reason/error leaked");
        puts("Playback diagnostics: ABI, forwarding, block/return identity, snapshot scope, counts and redaction passed");
    }
    return 0;
}
