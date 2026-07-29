# Termux-iOS — standalone terminal app

This archive contains only the Termux-iOS terminal project for iOS 15/16, iPhone 8, palera1n rootless (`/var/jb`) and TrollStore.

Included:

- SwiftUI/UIKit terminal app in `Termux-iOS/`;
- UIKit `UIKeyInput` keyboard bridge and extra keys;
- terminal buffer, VT100 parser, PTY, and themes;
- native `jb-chroot` helper;
- pacman-only bootstrap with `pkg`, `pacman.conf`, and mirrorlist;
- `apt`/`apt-get` guards;
- TrollStore build scripts for `Termux-iOS.ipa` and `Termux-iOS.tipa`.


## Check for Arch Linux

```bash
make check
```

## Build

A complete iOS build requires Xcode / the iPhoneOS SDK. Without macOS, you can use the GitHub Actions workflow or set up a compatible iOS cross-toolchain.

```bash
IOS_SDK=/path/to/iphoneos.sdk IOS_CLANG=/path/to/clang make
```
