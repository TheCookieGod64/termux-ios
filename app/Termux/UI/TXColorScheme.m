//
//  TXColorScheme.m
//

#import "TXColorScheme.h"

static UIColor *TXColorFromHex(uint32_t hex) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:1.0];
}

@implementation TXColorScheme {
    UIColor *_palette[256];
}

+ (instancetype)schemeNamed:(NSString *)name
                 background:(uint32_t)background
                 foreground:(uint32_t)foreground
                     cursor:(uint32_t)cursor
                   ansi:(const uint32_t *)ansi {
    TXColorScheme *scheme = [[TXColorScheme alloc] init];
    scheme->_name = [name copy];
    scheme->_defaultBackground = TXColorFromHex(background);
    scheme->_defaultForeground = TXColorFromHex(foreground);
    scheme->_cursorColor = TXColorFromHex(cursor);
    scheme->_selectionColor = [TXColorFromHex(cursor) colorWithAlphaComponent:0.35];

    // 0-15: the scheme's ANSI colours.
    for (int i = 0; i < 16; i++) {
        scheme->_palette[i] = TXColorFromHex(ansi[i]);
    }
    // 16-231: the 6x6x6 colour cube.
    static const int levels[6] = {0, 95, 135, 175, 215, 255};
    for (int i = 0; i < 216; i++) {
        int r = levels[(i / 36) % 6];
        int g = levels[(i / 6) % 6];
        int b = levels[i % 6];
        scheme->_palette[16 + i] =
            TXColorFromHex((uint32_t)((r << 16) | (g << 8) | b));
    }
    // 232-255: the greyscale ramp.
    for (int i = 0; i < 24; i++) {
        int value = 8 + i * 10;
        scheme->_palette[232 + i] =
            TXColorFromHex((uint32_t)((value << 16) | (value << 8) | value));
    }
    return scheme;
}

+ (instancetype)defaultScheme {
    static TXColorScheme *scheme;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        static const uint32_t ansi[16] = {
            0x000000, 0xCD3131, 0x0DBC79, 0xE5E510,
            0x2472C8, 0xBC3FBC, 0x11A8CD, 0xE5E5E5,
            0x666666, 0xF14C4C, 0x23D18B, 0xF5F543,
            0x3B8EEA, 0xD670D6, 0x29B8DB, 0xFFFFFF,
        };
        scheme = [self schemeNamed:@"Termux Dark" background:0x0E0E0E
                        foreground:0xE6E6E6 cursor:0x00E676 ansi:ansi];
    });
    return scheme;
}

+ (instancetype)solarizedDarkScheme {
    static TXColorScheme *scheme;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        static const uint32_t ansi[16] = {
            0x073642, 0xDC322F, 0x859900, 0xB58900,
            0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5,
            0x002B36, 0xCB4B16, 0x586E75, 0x657B83,
            0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3,
        };
        scheme = [self schemeNamed:@"Solarized Dark" background:0x002B36
                        foreground:0x839496 cursor:0x93A1A1 ansi:ansi];
    });
    return scheme;
}

+ (instancetype)novaScheme {
    static TXColorScheme *scheme;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        static const uint32_t ansi[16] = {
            0x3C4C55, 0xDF8C8C, 0xA8CE93, 0xDADA93,
            0x83AFE5, 0x9A93E1, 0x7FC1CA, 0xC5D4DD,
            0x556873, 0xDF8C8C, 0xA8CE93, 0xDADA93,
            0x83AFE5, 0x9A93E1, 0x7FC1CA, 0xE6EEF3,
        };
        scheme = [self schemeNamed:@"Nova" background:0x1E272C
                        foreground:0xC5D4DD cursor:0x7FC1CA ansi:ansi];
    });
    return scheme;
}

+ (NSArray<TXColorScheme *> *)allSchemes {
    return @[[self defaultScheme], [self solarizedDarkScheme], [self novaScheme]];
}

- (UIColor *)colorForTerminalColor:(TXColor)color
                      isForeground:(BOOL)isForeground
                              bold:(BOOL)bold {
    if (color.isTrueColor) {
        return TXColorFromHex(color.value);
    }
    if (color.value == TXColorDefaultIndex) {
        return isForeground ? self.defaultForeground : self.defaultBackground;
    }

    uint32_t index = color.value;
    // Bold text uses the bright variant of the first eight colours, which is
    // what every terminal has done since the eighties.
    if (bold && isForeground && index < 8) index += 8;
    if (index > 255) index = 255;
    return _palette[index] ?: self.defaultForeground;
}

@end
