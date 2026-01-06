#import <Foundation/Foundation.h>
#import <Mobile/Mobile.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Creates a gomobile `MobileParser` instance using the generated factory
/// `MobileCreateParser` from the Mobile framework.
/// Returns `nil` and sets `error` when parser creation fails.
MobileParser * _Nullable CreateMobileParser(NSString * _Nullable pks1Dir,
                                            NSString * _Nullable pks2Dir,
                                            NSError ** _Nullable error);

#ifdef __cplusplus
}
#endif
