//
//  TXKeyboardAccessoryView.m
//

#import "TXKeyboardAccessoryView.h"

typedef NS_ENUM(NSInteger, TXModifierState) {
    TXModifierStateOff = 0,
    TXModifierStateOneShot,
    TXModifierStateLocked,
};

@interface TXKeyButton : UIButton
@property (nonatomic, copy) NSString *keyName;      // special key, or nil
@property (nonatomic, copy) NSString *keyText;      // literal text, or nil
@property (nonatomic) BOOL isModifier;
@end

@implementation TXKeyButton
@end

@implementation TXKeyboardAccessoryView {
    UIScrollView *_scrollView;
    UIStackView *_stackView;
    TXKeyButton *_controlButton;
    TXKeyButton *_altButton;
    TXModifierState _controlState;
    TXModifierState _altState;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor = [UIColor colorWithWhite:0.11 alpha:1.0];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    _scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scrollView.showsHorizontalScrollIndicator = NO;
    _scrollView.alwaysBounceHorizontal = YES;
    [self addSubview:_scrollView];

    _stackView = [[UIStackView alloc] init];
    _stackView.axis = UILayoutConstraintAxisHorizontal;
    _stackView.spacing = 6;
    _stackView.alignment = UIStackViewAlignmentFill;
    _stackView.distribution = UIStackViewDistributionFill;
    _stackView.layoutMargins = UIEdgeInsetsMake(6, 8, 6, 8);
    _stackView.layoutMarginsRelativeArrangement = YES;
    _stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [_scrollView addSubview:_stackView];

    [NSLayoutConstraint activateConstraints:@[
        [_stackView.leadingAnchor constraintEqualToAnchor:_scrollView.leadingAnchor],
        [_stackView.trailingAnchor constraintEqualToAnchor:_scrollView.trailingAnchor],
        [_stackView.topAnchor constraintEqualToAnchor:_scrollView.topAnchor],
        [_stackView.bottomAnchor constraintEqualToAnchor:_scrollView.bottomAnchor],
        [_stackView.heightAnchor constraintEqualToAnchor:_scrollView.heightAnchor],
    ]];

    [self buildKeys];
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, 44);
}

#pragma mark - Key layout

- (void)buildKeys {
    // Order chosen to match Termux's default extra-keys row, with the most
    // used keys reachable by the thumb.
    _controlButton = [self addKeyWithTitle:@"CTRL" name:nil text:nil modifier:YES];
    _altButton = [self addKeyWithTitle:@"ALT" name:nil text:nil modifier:YES];

    [self addKeyWithTitle:@"ESC" name:@"escape" text:nil modifier:NO];
    [self addKeyWithTitle:@"TAB" name:@"tab" text:nil modifier:NO];
    [self addKeyWithTitle:@"←" name:@"left" text:nil modifier:NO];
    [self addKeyWithTitle:@"↓" name:@"down" text:nil modifier:NO];
    [self addKeyWithTitle:@"↑" name:@"up" text:nil modifier:NO];
    [self addKeyWithTitle:@"→" name:@"right" text:nil modifier:NO];
    [self addKeyWithTitle:@"⇱" name:@"home" text:nil modifier:NO];
    [self addKeyWithTitle:@"⇲" name:@"end" text:nil modifier:NO];
    [self addKeyWithTitle:@"PGUP" name:@"pageup" text:nil modifier:NO];
    [self addKeyWithTitle:@"PGDN" name:@"pagedown" text:nil modifier:NO];

    for (NSString *character in @[@"-", @"/", @"|", @"~", @"$", @"*", @"^", @"&",
                                  @"<", @">", @"{", @"}", @"[", @"]", @"(", @")",
                                  @"'", @"\"", @"`", @"=", @"+", @"_", @"#", @"%",
                                  @"!", @"?", @":", @";", @"\\"]) {
        [self addKeyWithTitle:character name:nil text:character modifier:NO];
    }

    for (int i = 1; i <= 12; i++) {
        NSString *name = [NSString stringWithFormat:@"f%d", i];
        [self addKeyWithTitle:name.uppercaseString name:name text:nil modifier:NO];
    }
}

- (TXKeyButton *)addKeyWithTitle:(NSString *)title
                            name:(NSString *)name
                            text:(NSString *)text
                        modifier:(BOOL)modifier {
    TXKeyButton *button = [TXKeyButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
    [button setTitleColor:[UIColor colorWithWhite:0.92 alpha:1.0] forState:UIControlStateNormal];
    button.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    button.layer.cornerRadius = 6;
    button.keyName = name;
    button.keyText = text;
    button.isModifier = modifier;
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);

    [button addTarget:self action:@selector(keyTapped:) forControlEvents:UIControlEventTouchUpInside];
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:38].active = YES;

    [_stackView addArrangedSubview:button];
    return button;
}

#pragma mark - Actions

- (void)keyTapped:(TXKeyButton *)button {
    UIImpactFeedbackGenerator *feedback =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];

    if (button.isModifier) {
        BOOL isControl = (button == _controlButton);
        TXModifierState state = isControl ? _controlState : _altState;

        // off -> one-shot -> locked -> off
        state = (state + 1) % 3;
        if (isControl) _controlState = state; else _altState = state;

        [self refreshModifierAppearance];
        [self.delegate accessoryViewDidChangeModifiers:self];
        return;
    }

    if (button.keyName) {
        [self.delegate accessoryView:self didTapSpecialKey:button.keyName];
    } else if (button.keyText) {
        [self.delegate accessoryView:self
                          didTapText:button.keyText
                             control:self.controlActive
                                 alt:self.altActive];
    }
    [self consumeModifiers];
}

- (BOOL)controlActive { return _controlState != TXModifierStateOff; }
- (BOOL)altActive { return _altState != TXModifierStateOff; }

- (void)consumeModifiers {
    BOOL changed = NO;
    if (_controlState == TXModifierStateOneShot) { _controlState = TXModifierStateOff; changed = YES; }
    if (_altState == TXModifierStateOneShot) { _altState = TXModifierStateOff; changed = YES; }
    if (changed) {
        [self refreshModifierAppearance];
        [self.delegate accessoryViewDidChangeModifiers:self];
    }
}

- (void)refreshModifierAppearance {
    [self styleModifierButton:_controlButton state:_controlState];
    [self styleModifierButton:_altButton state:_altState];
}

- (void)styleModifierButton:(TXKeyButton *)button state:(TXModifierState)state {
    switch (state) {
        case TXModifierStateOff:
            button.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
            [button setTitleColor:[UIColor colorWithWhite:0.92 alpha:1.0]
                         forState:UIControlStateNormal];
            break;
        case TXModifierStateOneShot:
            button.backgroundColor = [UIColor colorWithRed:0.0 green:0.55 blue:0.35 alpha:1.0];
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            break;
        case TXModifierStateLocked:
            button.backgroundColor = [UIColor colorWithRed:0.0 green:0.75 blue:0.45 alpha:1.0];
            [button setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
            break;
    }
}

@end
