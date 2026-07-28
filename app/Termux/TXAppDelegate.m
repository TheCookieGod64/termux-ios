//
//  TXAppDelegate.m
//

#import "TXAppDelegate.h"

#import "TXBootstrap.h"
#import "TXTerminalViewController.h"

#import <signal.h>

@implementation TXAppDelegate {
    UIBackgroundTaskIdentifier _backgroundTask;
}

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Writing to a pty whose reader has gone away raises SIGPIPE, which would
    // kill the app.  We handle short writes ourselves instead.
    signal(SIGPIPE, SIG_IGN);
    // Reap children that nobody is waiting on so we do not leak zombies.
    signal(SIGCHLD, SIG_DFL);

    NSError *error = nil;
    if (![[TXBootstrap sharedBootstrap] prepareDirectoriesWithError:&error]) {
        NSLog(@"[Termux] could not prepare directories: %@", error);
    }

    _backgroundTask = UIBackgroundTaskInvalid;

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[TXTerminalViewController alloc] init];
    self.window.backgroundColor = UIColor.blackColor;
    [self.window makeKeyAndVisible];

    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Keep the shell alive for as long as iOS allows so a long build or
    // download survives the user checking their messages.
    if (_backgroundTask != UIBackgroundTaskInvalid) return;

    __weak typeof(self) weakSelf = self;
    _backgroundTask = [application beginBackgroundTaskWithName:@"dev.termux.ios.session"
                                             expirationHandler:^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [application endBackgroundTask:strongSelf->_backgroundTask];
        strongSelf->_backgroundTask = UIBackgroundTaskInvalid;
    }];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    if (_backgroundTask == UIBackgroundTaskInvalid) return;
    [application endBackgroundTask:_backgroundTask];
    _backgroundTask = UIBackgroundTaskInvalid;
}

@end
