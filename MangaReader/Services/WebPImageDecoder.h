#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WebPImageDecoder : NSObject

+ (nullable UIImage *)decodeWebPData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
