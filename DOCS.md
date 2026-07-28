# Termux-iOS — Technical Documentation & Architecture

## 1. Architectural Overview

Termux-iOS is structured into three primary architectural tiers:
1. **The iOS Application UI & Terminal Emulation Layer (Swift / SwiftUI / UIKit)**
2. **The Jailbreak Container & Chroot Execution Engine (Native C — `jb-chroot`)**
3. **The Rootfs Ecosystem & Package Manager Layer (`pacman`, `pkg`, `rootfs-bootstrap`)**

```
+---------------------------------------------------------------------------------+
|                         Termux-iOS Application (SwiftUI)                         |
|  +--------------------+  +--------------------+  +---------------------------+  |
|  |   TerminalView     |  |   ExtraKeysView    |  |  SidebarView / Settings   |  |
|  +--------------------+  +--------------------+  +---------------------------+  |
+----------------------------------------+----------------------------------------+
                                         | PTY I/O & Signals (openpty / kill / winsize)
+----------------------------------------v----------------------------------------+
|                      Jailbreak Chroot Helper (C — jb-chroot)                    |
|  +-------------------------------------+-------------------------------------+  |
|  | UID==0: chroot("/var/jb")           | UID!=0: PROOT / Prefix Rootless     |  |
|  | PREFIX=/usr, HOME=/home/mobile      | PREFIX=/var/jb/usr, PATH=/var/jb... |  |
|  +-------------------------------------+-------------------------------------+  |
+----------------------------------------+----------------------------------------+
                                         | Spawns /bin/bash or /var/jb/usr/bin/bash
+----------------------------------------v----------------------------------------+
|                       Pacman Ecosystem & Termux Tools                           |
|  +-------------------------------------+-------------------------------------+  |
|  | Pacman Package Manager (No apt!)    | Termux CLI Tools                    |  |
|  | pacman.conf, mirrorlist, pkg wrapper| termux-info, termux-reload-settings |  |
|  +-------------------------------------+-------------------------------------+  |
+---------------------------------------------------------------------------------+
```

---

## 2. PTY & Chroot Execution (`jb-chroot.c`)

When a user launches Termux-iOS or creates a new session:
1. `PTYProcess` allocates a pseudo-terminal pair via `openpty()`.
2. It sets the terminal size using `ioctl(masterFD, TIOCSWINSZ, &winSize)`.
3. It forks and calls `execv()` on `/var/jb/usr/bin/jb-chroot` (or local `/usr/bin/jb-chroot` / `/bin/bash`).
4. `jb-chroot` evaluates execution privileges:
   - **Root / TrollStore Entitled Mode:** If running as UID 0, it executes `chroot("/var/jb")` and `chdir("/")`. It sets `PATH` to `/usr/local/bin:/usr/bin:/bin` and `PREFIX` to `/usr`.
   - **Rootless Prefix Mode:** If running without `chroot` privileges, it sets `PATH` to `/var/jb/usr/local/bin:/var/jb/usr/bin:/usr/bin:/bin` and `PREFIX` to `/var/jb/usr`.
5. In both modes, `TERM=xterm-256color`, `TERMUX_PKG_MANAGER=pacman`, and `HOME` are exported before launching the shell.

---

## 3. Package Management Policy: Why Pacman over Apt?

On standard iOS rootless jailbreaks (such as palera1n with Procursus), Debian's `apt`/`dpkg` suite is the default package manager. However, **Termux-iOS is engineered to use Pacman exclusively**.

### How Termux-iOS Enforces Pacman:
- **`rootfs-bootstrap/pacman.conf`**: Optimized for iOS `aarch64` architectures, setting database paths and mirrors within `/var/jb`.
- **`rootfs-bootstrap/pkg`**: The standard Termux CLI package manager wrapper is written in Bash to translate `pkg` subcommands into exact `pacman` flags:
  - `pkg install <pkg>` -> `pacman -S <pkg>`
  - `pkg remove <pkg>` -> `pacman -Rns <pkg>`
  - `pkg update` -> `pacman -Sy`
  - `pkg upgrade` -> `pacman -Syu`
- **`rootfs-bootstrap/apt` & `apt-get`**: Protective wrapper scripts are installed into `/var/jb/usr/bin/apt` and `apt-get` that intercept and reject any call to `apt`, printing instructions on how to use `pacman` or `pkg` instead.

---

## 4. TrollStore Packaging & Entitlements

TrollStore leverages a core iOS signature bug on iOS 15.0 – 16.7.x to install apps with arbitrary system entitlements.

### Essential Entitlements (`trollstore/Entitlements.plist`)
- `platform-application`: Bypasses standard sandbox rules.
- `com.apple.private.posix_spawn-allow`: Permits spawning native Unix binaries outside the application bundle.
- `com.apple.private.vfs.pivot-root`: Permits calling `chroot` and filesystem pivoting.
- `com.apple.private.security.no-sandbox`: Grants unrestricted rootfs read/write permissions.

### Build Workflow
The script `build-trollstore-ipa.sh` automatically compiles `jb-chroot`, bundles the script utilities and Pacman configurations, compiles the Swift app via Xcode (if present), and applies entitlements before assembling `Termux-iOS.tipa`.
