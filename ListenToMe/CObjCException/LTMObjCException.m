#import "include/LTMObjCException.h"

NSErrorDomain const LTMObjCExceptionErrorDomain = @"com.rexdanquah.listentome.ObjCException";
NSString * const LTMObjCExceptionNameKey = @"LTMObjCExceptionName";

@implementation LTMObjCException

+ (BOOL)catchExceptionInBlock:(NS_NOESCAPE void (^)(void))block
                        error:(NSError * _Nullable * _Nullable)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:LTMObjCExceptionErrorDomain
                                         code:1
                                     userInfo:@{
                LTMObjCExceptionNameKey: exception.name,
                NSLocalizedDescriptionKey: exception.reason ?: exception.name,
            }];
        }
        return NO;
    }
}

@end
