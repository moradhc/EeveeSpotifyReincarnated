#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <stdatomic.h>
#import <string.h>
#import <stdlib.h>
#import "NativeConfigDiagnostics.h"

// Passive probes for selectors verified in the supplied Spotify 9.1.98 binary.
// All arguments (including completion blocks) and return values pass unchanged.
// No arbitrary getters are invoked and no response bodies or tokens are logged.
static EEVConfigDiagnosticLogger EEVLogger;
static atomic_uint EEVCalls[7];
static const char *EEVNames[] = {
    "fetch", "fetch-account-attributes", "reconnect", "default-configuration",
    "default-fetch-time", "restore-provider", "last-fetch-time"
};

static void EEVLog(NSString *message) {
    if (EEVLogger) EEVLogger([[@"[NATIVE V3] " stringByAppendingString:message] UTF8String]);
}

static void EEVRecord(unsigned int index, NSString *detail) {
    unsigned int count = atomic_fetch_add_explicit(&EEVCalls[index], 1, memory_order_relaxed) + 1;
    if (count <= 8) {
        EEVLog([NSString stringWithFormat:@"call=%s n=%u %@", EEVNames[index], count, detail]);
    } else if (count == 9) {
        EEVLog([NSString stringWithFormat:@"call=%s further calls counted in summary", EEVNames[index]]);
    }
}

// Do not replace an inherited method or guess a changed ABI. Return/argument
// encodings are checked individually so frame offsets do not affect validation.
static Method EEVOwnMethod(Class cls, NSString *selectorName, NSArray<NSString *> *types) {
    if (!cls) return NULL;
    SEL selector = NSSelectorFromString(selectorName);
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    Method result = NULL;
    for (unsigned int i = 0; i < count; i++) {
        if (sel_isEqual(method_getName(methods[i]), selector)) { result = methods[i]; break; }
    }
    free(methods);
    if (!result || method_getNumberOfArguments(result) + 1 != types.count) return NULL;
    for (NSUInteger i = 0; i < types.count; i++) {
        char *actual = i == 0 ? method_copyReturnType(result)
                             : method_copyArgumentType(result, (unsigned int)i - 1);
        BOOL same = actual && strcmp(actual, types[i].UTF8String) == 0;
        // BOOL is encoded as c on some macOS test hosts, B on the supplied IPA.
        if (actual && [types[i] isEqualToString:@"B"] && strcmp(actual, "c") == 0) same = YES;
        free(actual);
        if (!same) return NULL;
    }
    return result;
}

static void EEVStatus(NSString *name, BOOL installed) {
    EEVLog([NSString stringWithFormat:@"probe=%@ %@", name,
            installed ? @"installed" : @"skipped (class, own method or signature unavailable)"]);
}

static void EEVInstallFetchers(void) {
    Class cls = NSClassFromString(@"_TtC22RemoteConfigurationSDK18FetcherObjCWrapper");
    SEL sel = NSSelectorFromString(@"fetchWithFetchType:timeout:completion:");
    Method method = EEVOwnMethod(cls, NSStringFromSelector(sel), @[@"v", @"@", @":", @"q", @"@", @"@?"]);
    if (method) {
        void (*original)(id, SEL, NSInteger, id, id) = (void (*)(id, SEL, NSInteger, id, id))method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^(id receiver, NSInteger type, id timeout, id completion) {
            EEVRecord(0, [NSString stringWithFormat:@"fetchType=%ld", (long)type]);
            original(receiver, sel, type, timeout, completion);
        });
        method_setImplementation(method, replacement);
    }
    EEVStatus(@"fetch", method != NULL);

    SEL attrSel = NSSelectorFromString(@"fetchWithFetchType:shouldHandleAccountAttributes:timeout:completion:");
    method = EEVOwnMethod(cls, NSStringFromSelector(attrSel), @[@"v", @"@", @":", @"q", @"B", @"@", @"@?"]);
    if (method) {
        void (*original)(id, SEL, NSInteger, BOOL, id, id) = (void (*)(id, SEL, NSInteger, BOOL, id, id))method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^(id receiver, NSInteger type, BOOL attributes, id timeout, id completion) {
            EEVRecord(1, [NSString stringWithFormat:@"fetchType=%ld handleAccountAttributes=%d", (long)type, attributes]);
            original(receiver, attrSel, type, attributes, timeout, completion);
        });
        method_setImplementation(method, replacement);
    }
    EEVStatus(@"fetch-account-attributes", method != NULL);

    SEL reconnectSel = NSSelectorFromString(@"onReconnectWithCompletion:");
    method = EEVOwnMethod(cls, NSStringFromSelector(reconnectSel), @[@"v", @"@", @":", @"@?"]);
    if (method) {
        void (*original)(id, SEL, id) = (void (*)(id, SEL, id))method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^(id receiver, id completion) {
            EEVRecord(2, @"");
            original(receiver, reconnectSel, completion);
        });
        method_setImplementation(method, replacement);
    }
    EEVStatus(@"reconnect", method != NULL);
}

static void EEVInstallBoolReader(Class cls, NSString *name, unsigned int index) {
    SEL sel = NSSelectorFromString(name);
    Method method = EEVOwnMethod(cls, name, @[@"B", @"@", @":"]);
    if (method) {
        BOOL (*original)(id, SEL) = (BOOL (*)(id, SEL))method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^BOOL(id receiver) {
            BOOL value = original(receiver, sel);
            EEVRecord(index, [NSString stringWithFormat:@"value=%d", value]);
            return value;
        });
        method_setImplementation(method, replacement);
    }
    EEVStatus(name, method != NULL);
}

static void EEVInstallReaders(void) {
    Class cls = NSClassFromString(@"_TtC22RemoteConfigurationSDK23ConfigurationReaderImpl");
    EEVInstallBoolReader(cls, @"isDefaultConfiguration", 3);
    EEVInstallBoolReader(cls, @"hasDefaultFetchTime", 4);

    SEL sel = NSSelectorFromString(@"restoreConfigurationProvider");
    Method method = EEVOwnMethod(cls, NSStringFromSelector(sel), @[@"@", @"@", @":"]);
    if (method) {
        id (*original)(id, SEL) = (id (*)(id, SEL))method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^id(id receiver) {
            id value = original(receiver, sel);
            EEVRecord(5, value ? @"returnedObject=yes" : @"returnedObject=no");
            return value;
        });
        method_setImplementation(method, replacement);
    }
    EEVStatus(@"restore-provider", method != NULL);

    SEL timeSel = NSSelectorFromString(@"lastFetchTime");
    method = EEVOwnMethod(cls, NSStringFromSelector(timeSel), @[@"q", @"@", @":"]);
    if (method) {
        NSInteger (*original)(id, SEL) = (NSInteger (*)(id, SEL))method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^NSInteger(id receiver) {
            NSInteger value = original(receiver, timeSel);
            EEVRecord(6, value == 0 ? @"zero=yes" : @"zero=no");
            return value;
        });
        method_setImplementation(method, replacement);
    }
    EEVStatus(@"last-fetch-time", method != NULL);
}

void EEVInstallNativeConfigDiagnostics(EEVConfigDiagnosticLogger logger) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        EEVLogger = logger;
        EEVLog(@"install begin; observation only");
        EEVInstallFetchers();
        EEVInstallReaders();
        EEVLog(@"install complete");
    });
}

void EEVNativeConfigDiagnosticsSummary(void) {
    for (unsigned int i = 0; i < 7; i++) {
        EEVLog([NSString stringWithFormat:@"summary call=%s total=%u", EEVNames[i],
                atomic_load_explicit(&EEVCalls[i], memory_order_relaxed)]);
    }
}
