//
//  TXTerminalViewController.m
//

#import "TXTerminalViewController.h"

#import "TXBootstrap.h"
#import "TXKeyboardAccessoryView.h"
#import "TXTerminalSession.h"
#import "TXTerminalView.h"

/// Default bootstrap: a Procursus-based arm64 rootfs.  Overridable in the UI so
/// users can point at their own build.
static NSString *const TXDefaultBootstrapURLKey = @"TXBootstrapURL";

@interface TXTerminalViewController () <TXTerminalViewDelegate,
                                        TXTerminalViewModifierSource,
                                        TXTerminalSessionDelegate,
                                        TXKeyboardAccessoryViewDelegate>
@end

@implementation TXTerminalViewController {
    TXTerminalView *_terminalView;
    TXKeyboardAccessoryView *_accessoryView;
    UIButton *_menuButton;
    UILabel *_titleLabel;

    NSMutableArray<TXTerminalSession *> *_sessions;
    NSInteger _activeSessionIndex;

    NSLayoutConstraint *_accessoryBottomConstraint;
    UIProgressView *_progressView;
    UILabel *_progressLabel;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    _sessions = [NSMutableArray array];
    _activeSessionIndex = -1;

    self.view.backgroundColor = [TXColorScheme defaultScheme].defaultBackground;

    [self buildTerminalView];
    [self buildAccessoryView];
    [self buildOverlayControls];
    [self observeKeyboard];

    [self createSession];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_terminalView becomeFirstResponder];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

#pragma mark - View construction

- (void)buildTerminalView {
    _terminalView = [[TXTerminalView alloc] initWithFrame:self.view.bounds];
    _terminalView.translatesAutoresizingMaskIntoConstraints = NO;
    _terminalView.delegate = self;
    _terminalView.modifierSource = self;
    [self.view addSubview:_terminalView];
}

- (void)buildAccessoryView {
    _accessoryView = [[TXKeyboardAccessoryView alloc] initWithFrame:CGRectZero];
    _accessoryView.translatesAutoresizingMaskIntoConstraints = NO;
    _accessoryView.delegate = self;
    [self.view addSubview:_accessoryView];

    _accessoryBottomConstraint =
        [_accessoryView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_terminalView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [_terminalView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
        [_terminalView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor],
        [_terminalView.bottomAnchor constraintEqualToAnchor:_accessoryView.topAnchor],

        [_accessoryView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_accessoryView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_accessoryView.heightAnchor constraintEqualToConstant:44],
        _accessoryBottomConstraint,
    ]];
}

- (void)buildOverlayControls {
    _menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _menuButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_menuButton setTitle:@"⋯" forState:UIControlStateNormal];
    _menuButton.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    [_menuButton setTitleColor:[UIColor colorWithWhite:0.8 alpha:0.85] forState:UIControlStateNormal];
    [_menuButton addTarget:self action:@selector(showMenu:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_menuButton];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _titleLabel.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    _titleLabel.textAlignment = NSTextAlignmentRight;
    [self.view addSubview:_titleLabel];

    _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _progressView.translatesAutoresizingMaskIntoConstraints = NO;
    _progressView.hidden = YES;
    _progressView.progressTintColor = [UIColor colorWithRed:0 green:0.85 blue:0.5 alpha:1];
    [self.view addSubview:_progressView];

    _progressLabel = [[UILabel alloc] init];
    _progressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _progressLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    _progressLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    _progressLabel.hidden = YES;
    _progressLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.view addSubview:_progressLabel];

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_menuButton.topAnchor constraintEqualToAnchor:safeArea.topAnchor constant:-2],
        [_menuButton.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-8],
        [_menuButton.widthAnchor constraintEqualToConstant:36],
        [_menuButton.heightAnchor constraintEqualToConstant:30],

        [_titleLabel.centerYAnchor constraintEqualToAnchor:_menuButton.centerYAnchor],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_menuButton.leadingAnchor constant:-6],

        [_progressView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:16],
        [_progressView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-16],
        [_progressView.bottomAnchor constraintEqualToAnchor:_accessoryView.topAnchor constant:-8],

        [_progressLabel.leadingAnchor constraintEqualToAnchor:_progressView.leadingAnchor],
        [_progressLabel.trailingAnchor constraintEqualToAnchor:_progressView.trailingAnchor],
        [_progressLabel.bottomAnchor constraintEqualToAnchor:_progressView.topAnchor constant:-4],
    ]];
}

#pragma mark - Keyboard

- (void)observeKeyboard {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(keyboardWillChangeFrame:)
                   name:UIKeyboardWillChangeFrameNotification object:nil];
    [center addObserver:self selector:@selector(keyboardWillHide:)
                   name:UIKeyboardWillHideNotification object:nil];
}

- (void)keyboardWillChangeFrame:(NSNotification *)notification {
    CGRect frame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:frame fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(converted));
    CGFloat inset = MAX(0, overlap - self.view.safeAreaInsets.bottom);

    NSTimeInterval duration =
        [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];

    _accessoryBottomConstraint.constant = -inset;
    [UIView animateWithDuration:duration > 0 ? duration : 0.25 animations:^{
        [self.view layoutIfNeeded];
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    _accessoryBottomConstraint.constant = 0;
    [UIView animateWithDuration:0.25 animations:^{
        [self.view layoutIfNeeded];
    }];
}

#pragma mark - Sessions

- (TXTerminalSession *)activeSession {
    if (_activeSessionIndex < 0 || _activeSessionIndex >= (NSInteger)_sessions.count) return nil;
    return _sessions[_activeSessionIndex];
}

- (void)createSession {
    [self.view layoutIfNeeded];

    NSInteger rows = _terminalView.rows;
    NSInteger columns = _terminalView.columns;

    TXTerminalSession *session = [[TXTerminalSession alloc] initWithRows:rows columns:columns];
    session.delegate = self;

    [_sessions addObject:session];
    _activeSessionIndex = (NSInteger)_sessions.count - 1;

    _terminalView.emulator = session.emulator;
    [_terminalView setNeedsScreenUpdate];

    NSError *error = nil;
    if (![session startWithError:&error]) {
        NSLog(@"[Termux] failed to start session: %@", error);
    }
    [self updateTitle];
}

- (void)switchToSessionAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_sessions.count) return;
    _activeSessionIndex = index;

    TXTerminalSession *session = _sessions[index];
    _terminalView.emulator = session.emulator;
    [session resizeToRows:_terminalView.rows columns:_terminalView.columns];
    [session.emulator.buffer markAllDirty];
    [_terminalView setNeedsScreenUpdate];
    [self updateTitle];
}

- (void)closeActiveSession {
    TXTerminalSession *session = [self activeSession];
    if (!session) return;

    [session terminate];
    [_sessions removeObjectAtIndex:_activeSessionIndex];

    if (_sessions.count == 0) {
        [self createSession];
    } else {
        [self switchToSessionAtIndex:MIN(_activeSessionIndex, (NSInteger)_sessions.count - 1)];
    }
}

- (void)updateTitle {
    TXTerminalSession *session = [self activeSession];
    if (!session) { _titleLabel.text = @""; return; }

    _titleLabel.text = _sessions.count > 1
        ? [NSString stringWithFormat:@"[%ld/%lu] %@",
           (long)(_activeSessionIndex + 1), (unsigned long)_sessions.count, session.title]
        : session.title;
}

#pragma mark - Menu

- (void)showMenu:(id)sender {
    UIAlertController *menu =
        [UIAlertController alertControllerWithTitle:@"Termux"
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;

    [menu addAction:[UIAlertAction actionWithTitle:@"New session"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [weakSelf createSession];
    }]];

    if (_sessions.count > 1) {
        [menu addAction:[UIAlertAction actionWithTitle:@"Next session"
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            typeof(self) strongSelf = weakSelf;
            NSInteger next = (strongSelf->_activeSessionIndex + 1) % (NSInteger)strongSelf->_sessions.count;
            [strongSelf switchToSessionAtIndex:next];
        }]];
    }

    [menu addAction:[UIAlertAction actionWithTitle:@"Paste"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        NSString *text = [UIPasteboard generalPasteboard].string;
        if (strongSelf && text) [strongSelf->_terminalView pasteText:text];
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Select all & copy"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf->_terminalView selectAll];
        [strongSelf->_terminalView copy:nil];
    }]];

    TXBootstrap *bootstrap = [TXBootstrap sharedBootstrap];
    NSString *bootstrapTitle = bootstrap.isInstalled ? @"Reinstall bootstrap..."
                                                     : @"Install bootstrap...";
    [menu addAction:[UIAlertAction actionWithTitle:bootstrapTitle
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [weakSelf promptForBootstrapURL];
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Appearance..."
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [weakSelf showAppearanceMenu];
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Close session"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *action) {
        [weakSelf closeActiveSession];
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];

    menu.popoverPresentationController.sourceView = _menuButton;
    menu.popoverPresentationController.sourceRect = _menuButton.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}

- (void)showAppearanceMenu {
    UIAlertController *menu =
        [UIAlertController alertControllerWithTitle:@"Appearance"
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;

    for (TXColorScheme *scheme in [TXColorScheme allSchemes]) {
        [menu addAction:[UIAlertAction actionWithTitle:scheme.name
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_terminalView.colorScheme = scheme;
            strongSelf.view.backgroundColor = scheme.defaultBackground;
        }]];
    }

    for (NSNumber *size in @[@10, @12, @14, @16]) {
        [menu addAction:[UIAlertAction actionWithTitle:
            [NSString stringWithFormat:@"Font size %@pt", size]
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_terminalView.font =
                [UIFont monospacedSystemFontOfSize:size.doubleValue weight:UIFontWeightRegular];
        }]];
    }

    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                             style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = _menuButton;
    menu.popoverPresentationController.sourceRect = _menuButton.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}

#pragma mark - Bootstrap installation

- (void)promptForBootstrapURL {
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:TXDefaultBootstrapURLKey];

    UIAlertController *prompt = [UIAlertController
        alertControllerWithTitle:@"Install bootstrap"
                         message:@"URL of a .tar or .tar.gz arm64 iOS rootfs "
                                 @"(Procursus-style).  It is unpacked into $PREFIX."
                  preferredStyle:UIAlertControllerStyleAlert];

    [prompt addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"https://example.com/bootstrap-arm64.tar.gz";
        field.text = saved;
        field.keyboardType = UIKeyboardTypeURL;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];

    __weak typeof(self) weakSelf = self;
    [prompt addAction:[UIAlertAction actionWithTitle:@"Install"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        NSString *text = prompt.textFields.firstObject.text;
        NSURL *url = text.length > 0 ? [NSURL URLWithString:text] : nil;
        if (!url) return;
        [[NSUserDefaults standardUserDefaults] setObject:text forKey:TXDefaultBootstrapURLKey];
        [weakSelf installBootstrapFromURL:url];
    }]];
    [prompt addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                               style:UIAlertActionStyleCancel handler:nil]];

    [self presentViewController:prompt animated:YES completion:nil];
}

- (void)installBootstrapFromURL:(NSURL *)url {
    _progressView.hidden = NO;
    _progressLabel.hidden = NO;
    _progressView.progress = 0;
    _progressLabel.text = @"Starting...";

    __weak typeof(self) weakSelf = self;
    [[TXBootstrap sharedBootstrap] installBootstrapFromURL:url
        progress:^(TXBootstrapStage stage, double fraction, NSString *message) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_progressView.progress = (float)fraction;
            strongSelf->_progressLabel.text = message;
        }
        completion:^(BOOL success, NSError *error) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_progressView.hidden = YES;
            strongSelf->_progressLabel.hidden = YES;

            if (success) {
                [[strongSelf activeSession] displayMessage:
                    @"\r\n\033[1;32mBootstrap installed.\033[0m "
                    @"Open a new session to use it.\r\n"];
            } else {
                [[strongSelf activeSession] displayMessage:
                    [NSString stringWithFormat:@"\r\n\033[1;31mBootstrap failed:\033[0m %@\r\n",
                     error.localizedDescription ?: @"unknown error"]];
            }
        }];
}

#pragma mark - TXTerminalViewDelegate

- (void)terminalView:(TXTerminalView *)view didProduceInput:(NSData *)data {
    [[self activeSession] writeData:data];
}

- (void)terminalView:(TXTerminalView *)view didResizeToRows:(NSInteger)rows columns:(NSInteger)columns {
    [[self activeSession] resizeToRows:rows columns:columns];
}

#pragma mark - TXTerminalSessionDelegate

- (void)sessionDidUpdateScreen:(TXTerminalSession *)session {
    if (session == [self activeSession]) {
        [_terminalView setNeedsScreenUpdate];
    }
}

- (void)sessionDidChangeTitle:(TXTerminalSession *)session {
    if (session == [self activeSession]) [self updateTitle];
}

- (void)session:(TXTerminalSession *)session didFinishWithReason:(NSString *)reason {
    // Leave the dead session on screen so the user can read the output; a new
    // session is only created when they ask for one.
    [self updateTitle];
}

#pragma mark - TXKeyboardAccessoryViewDelegate

- (void)accessoryView:(TXKeyboardAccessoryView *)view didTapSpecialKey:(NSString *)keyName {
    [_terminalView sendSpecialKey:keyName];
}

- (void)accessoryView:(TXKeyboardAccessoryView *)view
           didTapText:(NSString *)text
              control:(BOOL)control
                  alt:(BOOL)alt {
    [_terminalView sendText:text control:control alt:alt];
}

- (void)accessoryViewDidChangeModifiers:(TXKeyboardAccessoryView *)view {
    // The terminal view asks the accessory for modifier state when a plain key
    // is typed, so nothing else to do here.
}

#pragma mark - TXTerminalViewModifierSource

- (BOOL)terminalViewControlModifierActive:(TXTerminalView *)view {
    return _accessoryView.controlActive;
}

- (BOOL)terminalViewAltModifierActive:(TXTerminalView *)view {
    return _accessoryView.altActive;
}

- (void)terminalViewDidConsumeModifiers:(TXTerminalView *)view {
    [_accessoryView consumeModifiers];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
