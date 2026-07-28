//
//  TXColorScheme.h
//  Maps terminal colour indices to UIColors.
//

#import <UIKit/UIKit.h>
#import "TXTerminalBuffer.h"

NS_ASSUME_NONNULL_BEGIN

@interface TXColorScheme : NSObject

@property (nonatomic, readonly, copy) NSString *name;

@property (nonatomic, readonly) UIColor *defaultForeground;
@property (nonatomic, readonly) UIColor *defaultBackground;
@property (nonatomic, readonly) UIColor *cursorColor;
@property (nonatomic, readonly) UIColor *selectionColor;

+ (instancetype)defaultScheme;      // Termux-like dark
+ (instancetype)solarizedDarkScheme;
+ (instancetype)novaScheme;
+ (NSArray<TXColorScheme *> *)allSchemes;

/// Resolves a cell colour, honouring bold-as-bright and inverse video.
- (UIColor *)colorForTerminalColor:(TXColor)color
                       isForeground:(BOOL)isForeground
                              bold:(BOOL)bold;

@end

NS_ASSUME_NONNULL_END
