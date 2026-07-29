# Termux-iOS — standalone terminal app

Dit archief bevat alleen het Termux-iOS-terminalproject voor iOS 15/16, iPhone 8, palera1n rootless (`/var/jb`) en TrollStore.

Inbegrepen:

- SwiftUI/UIKit-terminalapp in `Termux-iOS/`;
- UIKit `UIKeyInput` keyboard bridge en Extra Keys;
- terminalbuffer, VT100-parser, PTY en thema’s;
- native `jb-chroot` helper;
- pacman-only bootstrap met `pkg`, `pacman.conf` en mirrorlist;
- `apt`/`apt-get` guards;
- TrollStore buildscript voor `Termux-iOS.ipa` en `Termux-iOS.tipa`.

`JITAllower` is niet opgenomen.

## Controleren op Arch Linux

```bash
make check
```

## Bouwen

Een volledige iOS-build heeft Xcode/iPhoneOS SDK nodig. Zonder macOS kun je de GitHub Actions-workflow gebruiken of een compatibele iOS-cross-toolchain instellen.

```bash
IOS_SDK=/pad/naar/iphoneos.sdk IOS_CLANG=/pad/naar/clang make
```
