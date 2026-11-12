#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import "NativeConfigDiagnostics.h"

static NSMutableArray<NSString *> *logs;
static id expectedTimeout, expectedCompletion, provider, fetcher, reader;
static unsigned int calls[7];

static void require(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); abort(); }
}
static void logger(const char *message) { [logs addObject:[NSString stringWithUTF8String:message]]; }
static BOOL logged(NSString *needle) {
    for (NSString *line in logs) if ([line containsString:needle]) return YES;
    return NO;
}
static void fetch(id self, SEL cmd, NSInteger type, id timeout, id completion) {
    (void)cmd;
    require(self == fetcher && type == 123 && timeout == expectedTimeout && completion == expectedCompletion,
            @"fetch arguments or callback identity changed");
    calls[0]++;
    ((void (^)(void))completion)();
}
static void fetchAttributes(id self, SEL cmd, NSInteger type, BOOL attributes, id timeout, id completion) {
    (void)cmd;
    require(self == fetcher && type == 456 && attributes && timeout == expectedTimeout && completion == expectedCompletion,
            @"attribute fetch arguments or callback identity changed");
    calls[1]++;
    ((void (^)(void))completion)();
}
static void reconnect(id self, SEL cmd, id completion) {
    (void)cmd;
    require(self == fetcher && completion == expectedCompletion, @"reconnect arguments changed");
    calls[2]++;
    ((void (^)(void))completion)();
}
static BOOL defaultConfiguration(id self, SEL cmd) {
    (void)cmd; require(self == reader, @"reader identity changed"); calls[3]++; return YES;
}
static BOOL defaultTime(id self, SEL cmd) {
    (void)cmd; require(self == reader, @"reader identity changed"); calls[4]++; return NO;
}
static id restore(id self, SEL cmd) {
    (void)cmd; require(self == reader, @"reader identity changed"); calls[5]++; return provider;
}
static NSInteger lastTime(id self, SEL cmd) {
    (void)cmd; require(self == reader, @"reader identity changed"); calls[6]++; return 4242;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        logs = [NSMutableArray array];
        BOOL mismatch = argc > 1 && strcmp(argv[1], "mismatch") == 0;
        Class fetchClass = objc_allocateClassPair([NSObject class], "_TtC22RemoteConfigurationSDK18FetcherObjCWrapper", 0);
        Class readerParent = [NSObject class];
        if (mismatch) {
            readerParent = objc_allocateClassPair([NSObject class], "EEVFixtureReaderParent", 0);
            class_addMethod(readerParent, NSSelectorFromString(@"isDefaultConfiguration"), (IMP)defaultConfiguration, "B16@0:8");
            objc_registerClassPair(readerParent);
        }
        Class readerClass = objc_allocateClassPair(readerParent, "_TtC22RemoteConfigurationSDK23ConfigurationReaderImpl", 0);
        require(fetchClass && readerClass, @"cannot create fixture classes");
        SEL fetchSel = NSSelectorFromString(@"fetchWithFetchType:timeout:completion:");
        class_addMethod(fetchClass, fetchSel, (IMP)fetch, mismatch ? "v40@0:8@16@24@?32" : "v40@0:8q16@24@?32");
        SEL attributesSel = NSSelectorFromString(@"fetchWithFetchType:shouldHandleAccountAttributes:timeout:completion:");
        class_addMethod(fetchClass, attributesSel, (IMP)fetchAttributes, "v44@0:8q16B24@28@?36");
        SEL reconnectSel = NSSelectorFromString(@"onReconnectWithCompletion:");
        class_addMethod(fetchClass, reconnectSel, (IMP)reconnect, "v24@0:8@?16");
        SEL defaultSel = NSSelectorFromString(@"isDefaultConfiguration");
        SEL defaultTimeSel = NSSelectorFromString(@"hasDefaultFetchTime");
        SEL restoreSel = NSSelectorFromString(@"restoreConfigurationProvider");
        SEL timeSel = NSSelectorFromString(@"lastFetchTime");
        if (!mismatch) class_addMethod(readerClass, defaultSel, (IMP)defaultConfiguration, "B16@0:8");
        class_addMethod(readerClass, defaultTimeSel, (IMP)defaultTime, "B16@0:8");
        class_addMethod(readerClass, restoreSel, (IMP)restore, "@16@0:8");
        class_addMethod(readerClass, timeSel, (IMP)lastTime, "q16@0:8");
        objc_registerClassPair(fetchClass);
        objc_registerClassPair(readerClass);
        fetcher = [[fetchClass alloc] init]; reader = [[readerClass alloc] init];
        expectedTimeout = @{@"private": @"DO_NOT_LOG_TIMEOUT_CONTENT"}; provider = [NSObject new];
        __block unsigned int completions = 0;
        expectedCompletion = [^{ completions++; } copy];

        EEVInstallNativeConfigDiagnostics(logger);
        EEVInstallNativeConfigDiagnostics(logger);
        if (mismatch) {
            require(method_getImplementation(class_getInstanceMethod(fetchClass, fetchSel)) == (IMP)fetch,
                    @"mismatched ABI was replaced");
            require(logged(@"probe=fetch skipped"), @"missing signature-mismatch diagnostic");
            require(method_getImplementation(class_getInstanceMethod(readerParent, defaultSel)) == (IMP)defaultConfiguration,
                    @"inherited superclass method was replaced");
            require(logged(@"probe=isDefaultConfiguration skipped"), @"inherited method not skipped");
            puts("Native configuration diagnostics: ABI mismatch and inherited method skipped");
            return 0;
        }

        ((void (*)(id, SEL, NSInteger, id, id))method_getImplementation(class_getInstanceMethod(fetchClass, fetchSel)))
            (fetcher, fetchSel, 123, expectedTimeout, expectedCompletion);
        ((void (*)(id, SEL, NSInteger, BOOL, id, id))method_getImplementation(class_getInstanceMethod(fetchClass, attributesSel)))
            (fetcher, attributesSel, 456, YES, expectedTimeout, expectedCompletion);
        ((void (*)(id, SEL, id))method_getImplementation(class_getInstanceMethod(fetchClass, reconnectSel)))
            (fetcher, reconnectSel, expectedCompletion);
        require(completions == 3 && calls[0] == 1 && calls[1] == 1 && calls[2] == 1,
                @"completion or original method called more than once");
        for (int i = 0; i < 20; i++) {
            BOOL value = ((BOOL (*)(id, SEL))method_getImplementation(class_getInstanceMethod(readerClass, defaultSel)))(reader, defaultSel);
            require(value, @"default-configuration return value changed");
        }
        require(!((BOOL (*)(id, SEL))method_getImplementation(class_getInstanceMethod(readerClass, defaultTimeSel)))(reader, defaultTimeSel),
                @"default-fetch-time return value changed");
        require(((id (*)(id, SEL))method_getImplementation(class_getInstanceMethod(readerClass, restoreSel)))(reader, restoreSel) == provider,
                @"restored provider identity changed");
        require(((NSInteger (*)(id, SEL))method_getImplementation(class_getInstanceMethod(readerClass, timeSel)))(reader, timeSel) == 4242,
                @"last-fetch-time return value changed");
        require(calls[3] == 20 && calls[4] == 1 && calls[5] == 1 && calls[6] == 1, @"reader call count changed");
        EEVNativeConfigDiagnosticsSummary();
        require(logged(@"summary call=default-configuration total=20"), @"summary lost throttled calls");
        require(logged(@"call=default-configuration further calls counted"), @"log throttle missing");
        require(!logged(@"DO_NOT_LOG_TIMEOUT_CONTENT"), @"private argument content logged");
        puts("Native configuration diagnostics: arguments, callbacks, returns, counts and throttling preserved");
    }
    return 0;
}
