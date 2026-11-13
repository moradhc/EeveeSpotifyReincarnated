#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <CommonCrypto/CommonDigest.h>
#import <stdint.h>
#import <stdlib.h>
#import <string.h>
#import "CommandOutcomeDiagnostics.h"
#import "PlaybackReasonVocabulary.h"

// Observation of generated context-player RPC callbacks, not return handles.
// Request/response identities, callback arguments, queues and return values are
// preserved. Wrapping changes callback identity, never its invocation count.
static EEVConfigDiagnosticLogger OCLogger;
static NSLock *OCLock;
static NSUInteger OCSequence;
static NSMutableDictionary<NSNumber *, NSString *> *OCPending;
static NSMutableDictionary<NSNumber *, NSNumber *> *OCReplies;
static NSSet<NSString *> *OCKnownReasons;

static void OCLog(NSString *line) {
    OCLogger([[@"[RESULT V10] " stringByAppendingString:line] UTF8String]);
}

static BOOL OCType(const char *actual, const char *expected) {
    return actual && (!strcmp(actual, expected) ||
        (!strcmp(expected, "@") && actual[0] == '@' && actual[1] == '"'));
}

static Method OCOwn(Class cls, NSString *name, NSArray<NSString *> *types) {
    if (!cls) return NULL;
    Method found = NULL; unsigned int count = 0;
    Method *list = class_copyMethodList(cls, &count);
    SEL sel = NSSelectorFromString(name);
    for (unsigned int i = 0; i < count; i++) if (sel_isEqual(method_getName(list[i]), sel)) { found = list[i]; break; }
    free(list);
    if (!found || method_getNumberOfArguments(found) + 1 != types.count) return NULL;
    for (NSUInteger i = 0; i < types.count; i++) {
        char *actual = i ? method_copyArgumentType(found, (unsigned int)i - 1) : method_copyReturnType(found);
        BOOL ok = OCType(actual, types[i].UTF8String); free(actual);
        if (!ok) return NULL;
    }
    return found;
}

// Apple Blocks ABI, including optional copy/dispose descriptor fields:
// https://clang.llvm.org/docs/Block-ABI-Apple.html
struct OCBlockLayout {
    void *isa;
    int32_t flags, reserved;
    void (*invoke)(void *, ...);
    const uintptr_t *descriptor;
};

static NSUInteger OCCallbackArity(id block) {
    if (!block) return 0;
    Class blockClass = NSClassFromString(@"NSBlock");
    if (!blockClass || ![block isKindOfClass:blockClass]) return 0;
    const struct OCBlockLayout *layout = (__bridge const void *)block;
    uint32_t flags = (uint32_t)layout->flags;
    if (!(flags & (1U << 30)) || (flags & (1U << 29)) || !layout->descriptor) return 0;
    NSUInteger offset = 2 + ((flags & (1U << 25)) ? 2 : 0);
    const char *encoding = (const char *)layout->descriptor[offset];
    if (!encoding) return 0;
    @try {
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:encoding];
        if (!signature || !signature.methodReturnType || strcmp(signature.methodReturnType, "v") ||
            (signature.numberOfArguments != 2 && signature.numberOfArguments != 3) ||
            strcmp([signature getArgumentTypeAtIndex:0], "@?")) return 0;
        for (NSUInteger i = 1; i < signature.numberOfArguments; i++)
            if (!OCType([signature getArgumentTypeAtIndex:i], "@")) return 0;
        return signature.numberOfArguments - 1;
    } @catch (__unused NSException *exception) { return 0; }
}

static NSString *OCReasons(id value) {
    if (![value isKindOfClass:[NSString class]]) return value ? @"unavailable" : @"none";
    NSString *text = value;
    if (!text.length) return @"none";
    if ([OCKnownReasons containsObject:text]) return text;
    if (text.length > 2048) return @"redacted-long-text";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-"];
    // Identify known tokens inside a compound reason without printing its text.
    NSMutableSet *known = [NSMutableSet set];
    for (NSString *token in [text componentsSeparatedByCharactersInSet:allowed.invertedSet])
        if ([OCKnownReasons containsObject:token]) [known addObject:token];
    if (known.count) return [@"known-tokens:" stringByAppendingString:
        [[[known allObjects] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","]];
    if (text.length <= 80 && [text rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound) {
        NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding]; unsigned char digest[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
        NSMutableString *hex = [NSMutableString string];
        for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
        return [@"unknown:sha256=" stringByAppendingString:hex];
    }
    return @"redacted-text";
}

static Method OCResponseGetter(id response, NSString *name, NSString *type) {
    Class cls = NSClassFromString(@"ESPResponseWithReasons");
    if (!cls || ![response isKindOfClass:cls]) return NULL;
    objc_property_t property = class_getProperty(cls, name.UTF8String);
    if (!property) return NULL;
    char *propertyType = property_copyAttributeValue(property, "T");
    BOOL valid = OCType(propertyType, type.UTF8String); free(propertyType);
    if (!valid || ![response respondsToSelector:NSSelectorFromString(name)]) return NULL;
    // Protobuf fields resolve dynamically. Validate the generated getter after
    // respondsToSelector has given the class the opportunity to resolve it.
    return OCOwn(cls, name, @[type, @"@", @":"]);
}

static NSString *OCError(id error) {
    if (!error) return @"none";
    if (![error isKindOfClass:[NSError class]]) return @"unrecognized-object";
    NSError *e = error;
    NSString *domain = [@[NSURLErrorDomain, NSCocoaErrorDomain, NSPOSIXErrorDomain] containsObject:e.domain] ? e.domain : @"other-domain";
    return [NSString stringWithFormat:@"%@:%ld", domain, (long)e.code];
}

static void OCReport(NSUInteger identifier, NSString *command, id response, id error) {
    [OCLock lock];
    NSUInteger occurrence = [OCReplies[@(identifier)] unsignedIntegerValue] + 1;
    OCReplies[@(identifier)] = @(occurrence); [OCPending removeObjectForKey:@(identifier)];
    [OCLock unlock];
    if (occurrence > 3) return; // Forward every callback; bound only diagnostic output.
    NSString *fields = response ? @"response=unrecognized" : @"response=nil";
    Method code = OCResponseGetter(response, @"error", @"i");
    Method reasons = OCResponseGetter(response, @"reasons", @"@");
    if (code) {
        int value = ((int (*)(id, SEL))method_getImplementation(code))(response, NSSelectorFromString(@"error"));
        id reason = reasons ? ((id (*)(id, SEL))method_getImplementation(reasons))(response, NSSelectorFromString(@"reasons")) : nil;
        fields = [NSString stringWithFormat:@"response=ESPResponseWithReasons error=%d reasons=[%@]", value, reasons ? OCReasons(reason) : @"getter-unavailable"];
    }
    if (!error && [response isKindOfClass:[NSError class]]) error = response;
    OCLog([NSString stringWithFormat:@"reply id=%lu command=%@ occurrence=%lu %@ transportError=%@",
        (unsigned long)identifier, command, (unsigned long)occurrence, fields, OCError(error)]);
}

static void OCSafeReport(NSUInteger identifier, NSString *command, id response, id error) {
    @try { OCReport(identifier, command, response, error); }
    @catch (__unused NSException *exception) {
        OCLog([NSString stringWithFormat:@"reply id=%lu command=%@ inspection-unavailable", (unsigned long)identifier, command]);
    }
}

void EEVInstallCommandOutcomeDiagnostics(const char *version, EEVConfigDiagnosticLogger logger) {
    if (strcmp(version, "9.1.98")) { logger("[RESULT V10] skipped unsupported-version"); return; }
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        OCLogger = logger; OCLock = [NSLock new];
        OCPending = [NSMutableDictionary dictionary]; OCReplies = [NSMutableDictionary dictionary];
        OCKnownReasons = [[NSSet setWithArray:EEVPlaybackReasonVocabularyV9()] setByAddingObjectsFromArray:
            @[@"not_playing_context", @"already_paused", @"not_paused", @"already_set", @"unknown"]];
        Class cls = NSClassFromString(@"ESPContextPlayerClientImpl");
        NSArray *commands = @[@"preparePlay", @"playPrepared", @"play", @"skipNext", @"skipPrev", @"seekTo", @"setOptions", @"setShufflingContext"];
        NSUInteger installed = 0;
        OCLog(@"install begin; response callbacks only; first 64 requests");
        for (NSString *command in commands) {
            NSString *name = [command stringByAppendingString:@":onResponse:"];
            Method method = OCOwn(cls, name, @[@"@", @"@", @":", @"@", @"@?"]);
            if (!method) { OCLog([@"skipped " stringByAppendingString:name]); continue; }
            IMP old = method_getImplementation(method); SEL sel = NSSelectorFromString(name);
            method_setImplementation(method, imp_implementationWithBlock(^id(id self, id request, id completion) {
                [OCLock lock]; NSUInteger identifier = ++OCSequence; [OCLock unlock];
                if (identifier > 64) return ((id (*)(id, SEL, id, id))old)(self, sel, request, completion);
                NSUInteger arity = OCCallbackArity(completion);
                if (!arity) {
                    OCLog([NSString stringWithFormat:@"request id=%lu command=%@ callback=unobserved-ABI-or-nil", (unsigned long)identifier, command]);
                    return ((id (*)(id, SEL, id, id))old)(self, sel, request, completion);
                }
                [OCLock lock]; OCPending[@(identifier)] = command; [OCLock unlock];
                OCLog([NSString stringWithFormat:@"request id=%lu command=%@ callbackObjects=%lu", (unsigned long)identifier, command, (unsigned long)arity]);
                id wrapped;
                if (arity == 1) {
                    void (^original)(id) = completion;
                    wrapped = [^(id response) {
                        OCSafeReport(identifier, command, response, nil); original(response);
                    } copy];
                } else {
                    void (^original)(id, id) = completion;
                    wrapped = [^(id response, id error) {
                        OCSafeReport(identifier, command, response, error); original(response, error);
                    } copy];
                }
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    [OCLock lock]; BOOL pending = OCPending[@(identifier)] != nil; [OCLock unlock];
                    if (pending) OCLog([NSString stringWithFormat:@"pending-after-10s id=%lu command=%@ (not a failure verdict)", (unsigned long)identifier, command]);
                });
                return ((id (*)(id, SEL, id, id))old)(self, sel, request, wrapped);
            }));
            installed++; OCLog([@"installed " stringByAppendingString:name]);
        }
        OCLog([NSString stringWithFormat:@"install complete; methods=%lu/8", (unsigned long)installed]);
    });
}
