#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <stdlib.h>
#import <string.h>
#import "CommandOutcomeDiagnostics.h"

@interface ESPResponseWithReasons : NSObject
@property(nonatomic) int error;
@property(nonatomic, copy) NSString *reasons;
@end
@implementation ESPResponseWithReasons
@end

static NSMutableArray<NSString *> *logs;
static id client, requestObject, returnObject, savedCallback, sentCallback, expectedResponse;
static NSUInteger originalCalls, originalCallbackCalls;
static BOOL synchronous;
static void check(BOOL ok, NSString *text) { if (!ok) { NSLog(@"FAIL %@", text); abort(); } }
static void logger(const char *line) { @synchronized(logs) { [logs addObject:[NSString stringWithUTF8String:line]]; } }
static BOOL logged(NSString *part) {
    @synchronized(logs) { for (NSString *line in logs) if ([line containsString:part]) return YES; }
    return NO;
}
static id fixtureSend(id self, SEL sel, id request, id callback) {
    (void)sel; check(self == client && request == requestObject, @"request identity/receiver changed");
    originalCalls++; sentCallback = callback; savedCallback = [callback copy];
    if (synchronous && callback) ((void (^)(id))callback)(expectedResponse);
    return returnObject;
}
static id invoke(id callback) {
    SEL sel = NSSelectorFromString(@"skipNext:onResponse:");
    IMP imp = [client methodForSelector:sel];
    return ((id (*)(id, SEL, id, id))imp)(client, sel, requestObject, callback);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        logs = [NSMutableArray array];
        NSString *mode = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"normal";
        BOOL unsupported = [mode isEqualToString:@"unsupported"];
        BOOL mismatch = [mode isEqualToString:@"mismatch"];
        BOOL inherited = [mode isEqualToString:@"inherited"];
        Class parent = [NSObject class];
        SEL selector = NSSelectorFromString(@"skipNext:onResponse:");
        if (inherited) {
            parent = objc_allocateClassPair(parent, "OutcomeParent", 0);
            check(class_addMethod(parent, selector, (IMP)fixtureSend, "@32@0:8@16@?24"), @"parent method");
            objc_registerClassPair(parent);
        }
        Class cls = objc_allocateClassPair(parent, "ESPContextPlayerClientImpl", 0);
        if (!inherited) check(class_addMethod(cls, selector, (IMP)fixtureSend, mismatch ? "@32@0:8@16q24" : "@32@0:8@16@?24"), @"fixture method");
        objc_registerClassPair(cls); client = [[cls alloc] init];
        requestObject = [NSObject new]; returnObject = [NSObject new];
        EEVInstallCommandOutcomeDiagnostics(unsupported ? "9.1.90" : "9.1.98", logger);
        if (unsupported || mismatch || inherited) {
            check([client methodForSelector:selector] == (IMP)fixtureSend, @"incompatible method changed");
            check(logged(@"skipped"), @"skip not reported");
            NSLog(@"PASS outcome diagnostics %@", mode); return 0;
        }
        IMP first = [client methodForSelector:selector];
        EEVInstallCommandOutcomeDiagnostics("9.1.98", logger);
        check(first == [client methodForSelector:selector] && originalCalls == 0, @"install invokes request or double wraps");
        ESPResponseWithReasons *response = [ESPResponseWithReasons new];
        response.error = 2; response.reasons = @"not_playing_context"; expectedResponse = response;
        void (^completion)(id) = [^(id value) {
            check(value == expectedResponse, @"response identity changed"); originalCallbackCalls++;
        } copy];
        check(invoke(completion) == returnObject && originalCalls == 1 && originalCallbackCalls == 0, @"request return or async ordering changed");
        check(savedCallback != completion, @"supported callback not wrapped");
        ((void (^)(id))savedCallback)(response);
        check(originalCallbackCalls == 1 && response.error == 2 && [response.reasons isEqual:@"not_playing_context"], @"response mutated");
        check(logged(@"reply id=1 command=skipNext occurrence=1 response=ESPResponseWithReasons error=2 reasons=[not_playing_context]"), @"response result missing");
        ((void (^)(id))savedCallback)(response);
        check(originalCallbackCalls == 2 && logged(@"occurrence=2"), @"repeated callback swallowed or duplicated");

        response.error = 0; response.reasons = @""; synchronous = YES;
        check(invoke(completion) == returnObject && originalCallbackCalls == 3, @"synchronous completion not forwarded");
        check(logged(@"error=0 reasons=[none]"), @"zero error absent");
        synchronous = NO;
        NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:-1009 userInfo:@{NSLocalizedDescriptionKey: @"PRIVATE_ERROR"}];
        __block NSUInteger pairCalls = 0;
        void (^pair)(id, NSError *) = [^(id value, NSError *err) {
            check(value == response && err == error, @"two callback arguments changed"); pairCalls++;
        } copy];
        invoke(pair); ((void (^)(id, id))savedCallback)(response, error);
        check(pairCalls == 1 && logged(@"transportError=NSURLErrorDomain:-1009"), @"transport error missing");

        response.reasons = @"command rejected: mft_disallow; PRIVATE_TEXT";
        invoke(completion); ((void (^)(id))savedCallback)(response);
        check(logged(@"reasons=[known-tokens:mft_disallow]"), @"compound reason not classified");
        response.reasons = @"PRIVATE_REASON";
        invoke(completion); ((void (^)(id))savedCallback)(response);
        check(logged(@"unknown:sha256=f00e013ca9289b975f7e4c2fc9fdf85f8150acbd504569145408b69662c18144"), @"unknown fingerprint mismatch");
        check(!logged(@"PRIVATE_"), @"private text leaked");

        __block NSUInteger scalarCalls = 0;
        void (^scalar)(int) = [^(int n) { check(n == 7, @"scalar argument changed"); scalarCalls++; } copy];
        invoke(scalar); check(sentCallback == scalar, @"unsupported ABI must be forwarded by identity");
        ((void (^)(int))savedCallback)(7); check(scalarCalls == 1, @"unobserved callback did not work");
        invoke(nil); check(sentCallback == nil, @"nil callback replaced");
        check(logged(@"callback=unobserved-ABI-or-nil"), @"unsupported callback not reported");

        expectedResponse = nil; invoke(completion); ((void (^)(id))savedCallback)(nil);
        check(logged(@"response=nil"), @"nil response mislabeled success");
        expectedResponse = [NSObject new]; invoke(completion); ((void (^)(id))savedCallback)(expectedResponse);
        check(logged(@"response=unrecognized"), @"unknown response not preserved");
        expectedResponse = response;
        // Bounded observation must not stop normal forwarding after request 64.
        while (originalCalls < 65) invoke(completion);
        check(sentCallback == completion && originalCalls == 65, @"observation limit altered forwarding");
        ((void (^)(id))savedCallback)(response);
        check(!logged(@"request id=65"), @"observation limit ineffective");
        NSLog(@"PASS outcome diagnostics forwarding, ABI, lifetime, ordering, redaction and observation limit");
    }
    return 0;
}
