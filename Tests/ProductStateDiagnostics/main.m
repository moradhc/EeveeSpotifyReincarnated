#import "ProductStateDiagnostics.h"
#import <objc/runtime.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <dispatch/dispatch.h>

static NSMutableArray<NSString *> *logs;
static unsigned int bridgeCalls;
static int sentinel;
static BOOL returnNull;
static id expectedReceiver;
static id expectedObserver, expectedScheduler;
static unsigned int observerCalls;

static void require(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); abort(); }
}
static void logger(const char *message) {
    @synchronized (logs) { [logs addObject:[NSString stringWithUTF8String:message]]; }
}
static BOOL logged(NSString *needle) {
    for (NSString *line in logs) if ([line containsString:needle]) return YES;
    return NO;
}
static void *bridge(id self, SEL cmd) {
    require(self == expectedReceiver && sel_isEqual(cmd, NSSelectorFromString(@"cppProductState")), @"bridge arguments changed");
    bridgeCalls++;
    return returnNull ? NULL : &sentinel;
}
static void addObserver(id self, SEL cmd, id observer, id scheduler) {
    require(self == expectedReceiver && sel_isEqual(cmd, NSSelectorFromString(@"addObserver:on:"))
            && observer == expectedObserver && scheduler == expectedScheduler, @"observer arguments changed");
    observerCalls++;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        logs = [NSMutableArray array];
        BOOL mismatch = argc > 1 && strcmp(argv[1], "mismatch") == 0;
        BOOL inherited = argc > 1 && strcmp(argv[1], "inherited") == 0;
        Class parent = [NSObject class];
        SEL selector = NSSelectorFromString(@"cppProductState");
        SEL observerSelector = NSSelectorFromString(@"addObserver:on:");
        if (inherited) {
            parent = objc_allocateClassPair(parent, "PSParentFixture", 0);
            class_addMethod(parent, selector, (IMP)bridge, "^v16@0:8");
            class_addMethod(parent, observerSelector, (IMP)addObserver, "v32@0:8@16@24");
            objc_registerClassPair(parent);
        }
        Class cls = objc_allocateClassPair(parent, "SPTCoreProductState", 0);
        require(cls != Nil, @"fixture class unavailable");
        if (!inherited) class_addMethod(cls, selector, (IMP)bridge, mismatch ? "@16@0:8" : "^v16@0:8");
        if (!inherited) class_addMethod(cls, observerSelector, (IMP)addObserver, mismatch ? "v32@0:8q16@24" : "v32@0:8@16@24");
        objc_registerClassPair(cls);
        expectedReceiver = [[cls alloc] init];
        expectedObserver = [NSObject new]; expectedScheduler = [NSObject new];

        // Before explicit opt-in, diagnostic entry points do nothing.
        EEVInstallProductStateBridgeProbe();
        EEVProductStateDictionary("values", @{}, @{});
        EEVProductStateGetter("string-getter", @"type", @"free", NO);
        EEVProductStateAds(YES, NO);
        EEVProductStateSummary();
        require(logs.count == 0 && method_getImplementation(class_getInstanceMethod(cls, selector)) == (IMP)bridge,
                @"diagnostics active before opt-in");

        EEVStartProductStateDiagnostics(logger);
        EEVStartProductStateDiagnostics(logger);
        EEVInstallProductStateBridgeProbe();
        IMP installed = method_getImplementation(class_getInstanceMethod(cls, selector));
        EEVInstallProductStateBridgeProbe();
        require(installed == method_getImplementation(class_getInstanceMethod(cls, selector)), @"duplicate bridge wrapper");
        if (mismatch || inherited) {
            require(installed == (IMP)bridge && logged(@"probe=cpp-bridge skipped"), @"unsafe bridge signature replaced");
            require(method_getImplementation(class_getInstanceMethod(cls, observerSelector)) == (IMP)addObserver
                    && logged(@"probe=add-observer skipped"), @"unsafe observer signature replaced");
            puts("Product state diagnostics: incompatible or inherited method skipped");
            return 0;
        }

        void *(*invoke)(id, SEL) = (void *(*)(id, SEL))installed;
        for (int i = 0; i < 20; i++) require(invoke(expectedReceiver, selector) == &sentinel, @"bridge pointer changed");
        returnNull = YES;
        require(invoke(expectedReceiver, selector) == NULL && bridgeCalls == 21, @"null pointer or call count changed");
        ((void (*)(id, SEL, id, id))method_getImplementation(class_getInstanceMethod(cls, observerSelector)))
            (expectedReceiver, observerSelector, expectedObserver, expectedScheduler);
        require(observerCalls == 1 && logged(@"observerClass=NSObject"), @"observer call changed or not recorded");

        NSMutableDictionary *input = [@{@"type": @"free", @"ads": @"1", @"on-demand": @0,
                                        @"email": @"PRIVATE_EMAIL", @"access_token": @"PRIVATE_TOKEN"} mutableCopy];
        NSDictionary *before = [input copy];
        for (int i = 0; i < 20; i++) EEVProductStateDictionary("set-original", input, input);
        require([input isEqualToDictionary:before], @"observed dictionary mutated");
        NSDictionary *premium = @{@"type": @"premium", @"ads": @"0", @"on-demand": @1};
        EEVProductStateDictionary("set-original", premium, premium);
        require(logged(@"event=set-original n=21 input={type=premium"), @"late transition lost after throttle");
        EEVProductStateDictionary("map-to-dictionary", input, premium);
        EEVProductStateDictionary("values", @{@"type": @"PRIVATE_PRODUCT", @"ads": @3}, @{});
        EEVProductStateDictionary("unknown-event-PRIVATE_EVENT", input, input);
        EEVProductStateGetter("string-getter", @"type", @"premium", YES);
        EEVProductStateGetter("string-getter", @"PRIVATE_KEY", @"PRIVATE_VALUE", NO);
        EEVProductStateGetter("subscript-getter", @"type", nil, NO);
        EEVProductStateAds(NO, YES);
        dispatch_apply(128, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(size_t index) {
            (void)index;
            EEVProductStateAds(NO, YES);
        });
        EEVProductStateSummary();
        require(logged(@"summary event=set-original total=21 inputFree=20 outputFree=20 inputAds1=20 outputAds1=20"), @"throttled input/output counts lost");
        require(logged(@"summary event=map-to-dictionary total=1 inputFree=1 outputFree=0 inputAds1=1 outputAds1=0"), @"before/after observations confused");
        require(logged(@"summary event=cpp-bridge total=21"), @"bridge summary incorrect");
        require(logged(@"summary event=ads-enabled total=129 inputFree=0 outputFree=0 inputAds1=0 outputAds1=0 forced=129"), @"concurrent counts lost");
        require(logged(@"key=type output=premium forced=1 original=not-read"), @"forced output mislabeled");
        require(logged(@"key=type output=missing forced=0 original=returned"), @"nil getter value lost");
        require(logged(@"trace=set-original") && logged(@"offset=0x") && logged(@"uuid="), @"symbolication metadata missing");
        require(!logged(@"PRIVATE_") && !logged(@"access_token") && !logged(@"email="), @"private data leaked");
        NSUInteger stateLines = 0;
        for (NSString *line in logs) if ([line containsString:@"event=set-original n="]) stateLines++;
        require(stateLines == 9, @"repeated state logs not throttled");
        puts("Product state diagnostics: opt-in, ABI, pointer identity, input/output, redaction, transitions and counts checked");
    }
    return 0;
}
