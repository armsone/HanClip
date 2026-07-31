#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "LogoMark" asset catalog image resource.
static NSString * const ACImageNameLogoMark AC_SWIFT_PRIVATE = @"LogoMark";

/// The "LogoMarkV2" asset catalog image resource.
static NSString * const ACImageNameLogoMarkV2 AC_SWIFT_PRIVATE = @"LogoMarkV2";

#undef AC_SWIFT_PRIVATE
