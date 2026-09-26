#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Architecture string MLX should use. A missing Metal name must not be passed
/// through: MLX builds a C++ string from UTF8String(), and a NULL pointer aborts
/// the process with no Swift error.
NSString *MLXMetalResolvedArchitecture(NSString *_Nullable reported, BOOL runningOnMac);

/// Installs the UTF-8 NULL guard and sets MLX_METAL_GPU_ARCH. Safe to call more than once.
void MLXMetalInstallStartupGuard(void);

NS_ASSUME_NONNULL_END
