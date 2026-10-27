#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Error domain for an Objective-C exception converted into an NSError.
/// userInfo carries the exception name under `LTMObjCExceptionNameKey` and
/// its reason under NSLocalizedDescriptionKey.
extern NSErrorDomain const LTMObjCExceptionErrorDomain;
extern NSString * const LTMObjCExceptionNameKey;

@interface LTMObjCException : NSObject

/// Runs `block`. If it raises an Objective-C exception, returns NO and fills
/// `error` instead of letting the exception terminate the app. Swift sees
/// this as `try LTMObjCException.catching { ... }`.
+ (BOOL)catchExceptionInBlock:(NS_NOESCAPE void (^)(void))block
                        error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(catching(_:));

@end

NS_ASSUME_NONNULL_END
