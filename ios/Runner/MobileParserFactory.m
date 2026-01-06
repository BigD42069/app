#import "MobileParserFactory.h"

MobileParser * _Nullable CreateMobileParser(NSString * _Nullable pks1Dir,
                                            NSString * _Nullable pks2Dir,
                                            NSError ** _Nullable error) {
  return MobileCreateParser(pks1Dir, pks2Dir, error);
}
