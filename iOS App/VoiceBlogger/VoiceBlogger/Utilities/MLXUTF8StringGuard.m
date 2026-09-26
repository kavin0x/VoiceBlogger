#import "MLXUTF8StringGuard.h"

#import <Metal/Metal.h>
#import <objc/runtime.h>

typedef const char *(*UTF8IMP)(id, SEL);

static BOOL mlxGuardInstalled = NO;

NSString *MLXMetalResolvedArchitecture(NSString *reported, BOOL runningOnMac) {
    if (reported.length > 0) {
        return reported;
    }
    // 'p' is the phone kernel family, 'g' is the base/pro Mac family.
    // Either is enough for MLX to skip the NULL architecture-name read.
    return runningOnMac ? @"applegpu_g14g" : @"applegpu_g15p";
}

static void installUTF8GuardOnClass(Class cls) {
    if (cls == Nil) {
        return;
    }
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int index = 0; index < count; index++) {
        if (method_getName(methods[index]) != @selector(UTF8String)) {
            continue;
        }
        UTF8IMP original = (UTF8IMP)method_getImplementation(methods[index]);
        id block = ^const char *(id self) {
            const char *raw = original(self, @selector(UTF8String));
            return raw != NULL ? raw : "";
        };
        method_setImplementation(methods[index], imp_implementationWithBlock(block));
    }
    free(methods);
}

static BOOL processIsRunningOnMac(void) {
#if TARGET_OS_MACCATALYST || TARGET_OS_OSX
    return YES;
#else
    if (@available(iOS 14.0, *)) {
        return NSProcessInfo.processInfo.isiOSAppOnMac;
    }
    return NO;
#endif
}

static NSString *reportedMetalArchitecture(void) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil || ![device respondsToSelector:@selector(architecture)]) {
        return nil;
    }
    MTLArchitecture *architecture = device.architecture;
    if (architecture == nil || ![architecture respondsToSelector:@selector(name)]) {
        return nil;
    }
    return architecture.name;
}

void MLXMetalInstallStartupGuard(void) {
    if (mlxGuardInstalled) {
        return;
    }
    mlxGuardInstalled = YES;

    // Metal's NSString cluster implements UTF8String on concrete classes.
    // MLX does std::string(utf8String()) and aborts when that pointer is NULL.
    installUTF8GuardOnClass(NSClassFromString(@"NSString"));
    installUTF8GuardOnClass(NSClassFromString(@"__NSCFString"));
    installUTF8GuardOnClass(NSClassFromString(@"NSTaggedPointerString"));
    installUTF8GuardOnClass(NSClassFromString(@"__NSCFConstantString"));
    installUTF8GuardOnClass(NSClassFromString(@"NSConstantString"));

    NSString *architecture = MLXMetalResolvedArchitecture(
        reportedMetalArchitecture(),
        processIsRunningOnMac()
    );
    const char *utf8 = architecture.UTF8String;
    if (utf8 == NULL || utf8[0] == '\0') {
        utf8 = processIsRunningOnMac() ? "applegpu_g14g" : "applegpu_g15p";
    }
    setenv("MLX_METAL_GPU_ARCH", utf8, 1);
}

__attribute__((constructor))
static void mlxMetalStartupConstructor(void) {
    MLXMetalInstallStartupGuard();
}
