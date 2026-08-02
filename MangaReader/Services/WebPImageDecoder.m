#import "WebPImageDecoder.h"
#import <libwebp/decode.h>

@implementation WebPImageDecoder

+ (nullable UIImage *)decodeWebPData:(NSData *)data {
    if (data.length == 0) {
        return nil;
    }

    WebPBitstreamFeatures features;
    if (WebPGetFeatures(data.bytes, data.length, &features) != VP8_STATUS_OK) {
        return nil;
    }
    if (features.width <= 0 || features.height <= 0) {
        return nil;
    }

    uint8_t *rgba = WebPDecodeRGBA(data.bytes, data.length, &features.width, &features.height);
    if (rgba == NULL) {
        return nil;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        rgba,
        features.width,
        features.height,
        8,
        features.width * 4,
        colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );
    CGImageRef cgImage = context ? CGBitmapContextCreateImage(context) : NULL;
    UIImage *image = cgImage ? [UIImage imageWithCGImage:cgImage scale:1.0 orientation:UIImageOrientationUp] : nil;

    if (cgImage) {
        CGImageRelease(cgImage);
    }
    if (context) {
        CGContextRelease(context);
    }
    CGColorSpaceRelease(colorSpace);
    WebPFree(rgba);
    return image;
}

@end
