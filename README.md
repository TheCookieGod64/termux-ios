# Termux for iOS

A Termux-style terminal emulator for **arm64 iOS**, built to be installed with
[TrollStore](https://github.com/opa334/TrollStore).

TrollStore installs apps with arbitrary entitlements permanently. That is what
makes this possible: with `platform-application` and
`com.apple.private.security.no-sandbox` the app leaves the iOS sandbox and
`posix_spawn()` starts working, so it can open a real pty and run real
processes — exactly what Termux does on Android.

The whole thing **cross-compiles from Linux**. No Mac, no Xcode, no Apple
developer account.

```
make toolchain     # one time: clang + iOS SDK + signer
make ipa           # -> build/Termux.ipa
```

Copy the `.ipa` to your iPhone and open it with TrollStore.

---

## What's in the box

| Piece | What it does |
|---|---|
| `app/Termux/Terminal` | VT100/VT220/xterm emulator: escape sequences, 256/truecolour, scrollback, alternate screen, wide characters |
| `app/Termux/Session` | pty allocation and `posix_spawn` of the shell, window resizing, signals |
| `app/Termux/UI` | CoreText renderer, gestures, hardware-keyboard support, the extra-key row |
| `app/Termux/Bootstrap` | Downloads and unpacks a Procursus arm64 rootfs, configures apt/dpkg |
| `native/xsh` | A small built-in shell so the terminal works *before* a bootstrap exists |
| `tools/fakesign.py` | Pure-python ad-hoc Mach-O signer with DER entitlements (replaces `ldid`) |

### Terminal features

Escape sequence support is broad enough for `vim`, `htop`, `less`, `tmux` and
friends:

- cursor movement, scrolling regions, insert/delete of lines and characters
- SGR: bold, dim, italic, underline, blink, inverse, strikethrough
- 16 / 256 / 24-bit truecolour, both `;` and `:` sub-parameter forms
- alternate screen buffer (`?1049`), bracketed paste (`?2004`)
- mouse reporting (X10, normal, button-event, any-event; SGR encoding)
- UTF-8 including combining marks and double-width CJK/emoji
- OSC window titles and OSC 52 clipboard integration
- DEC special graphics (line drawing), tab stops, save/restore cursor

### Interface

- pinch to change font size, drag to scroll, long-press to select and copy
- extra-key row: `ESC` `CTRL` `ALT` `TAB`, arrows, `PGUP`/`PGDN`, `F1`–`F12`
  and the punctuation iOS hides three taps deep
- sticky modifiers: tap `CTRL` once for the next key, twice to lock
- hardware keyboard: `Ctrl`+letter, `Alt`+letter, arrows, function keys
- multiple sessions, three colour schemes

---

## Building

You need `python3`, `git`, `make`, `cc` and about 3 GB of disk.

```bash
make toolchain     # downloads zig (clang) + the iOS SDKs into .toolchain/
make ipa           # builds and signs build/Termux.ipa
make test          # runs everything checkable on the host
```

### How the toolchain works

There is no official Apple toolchain for Linux, so this project assembles one:

- **compiler** — the `ziglang` wheel from PyPI. `zig cc` is a full clang driver
  with a Mach-O linker built in, so it targets `aarch64-ios` without `ld64`.
- **SDK** — [theos/sdks](https://github.com/theos/sdks) provides the iOS
  headers and `.tbd` stub libraries.
- **signing** — `tools/fakesign.py`, written for this project, attaches an
  ad-hoc code signature with a CodeDirectory, XML *and* DER entitlements. The
  DER blob matters: AMFI on iOS 15+ rejects entitlements without it.

Verify a build at any time:

```bash
python3 tools/verify_signature.py build/Payload/Termux.app/Termux
```

This re-hashes every page and checks the special slots — the closest thing to
`codesign -dv --entitlements -` available off a Mac.

---

## Installing on the phone

1. Have TrollStore installed (iPhone 8 on a TrollStore-capable iOS is fine).
2. Transfer `build/Termux.ipa` — AirDrop, a web server, the Files app, whatever.
3. Open it and choose **Install with TrollStore**.
4. Launch Termux. You get the built-in shell (`xsh`) immediately.

If the terminal shows *"Could not start a shell"*, the app was installed
without TrollStore and the entitlements were stripped.

---

## The userland

Out of the box you get `xsh`, a small shell bundled with the app: pipelines,
redirection, quoting, `$VAR` expansion, `&&`/`||`/`;`, and builtins (`cd`,
`ls`, `cat`, `cp`, `mv`, `rm`, `mkdir`, `which`, `chmod`, …). Enough to look
around and install the real thing.

For a full userland — bash, coreutils, git, python, apt — install a
[Procursus](https://github.com/ProcursusTeam/Procursus) bootstrap from the
menu (**⋯ → Install bootstrap**). Give it the URL of an `iphoneos-arm64`
rootfs tarball; it unpacks into `$PREFIX` inside the app container and writes
apt/dpkg configuration pointing everything at that prefix, so `apt install …`
works without needing `/` to be writable.

```
<container>/Documents/prefix/     $PREFIX
<container>/Documents/home/       $HOME
```

`.tar` and `.tar.gz` are supported natively. `.xz`/`.zst` are not — recompress
those to gzip first.

---

## Testing

```bash
make test
```

| Suite | Runs where | What it covers |
|---|---|---|
| `tests/test_fakesign.py` | host | DER encoding, superblob layout, page hashes, idempotent re-signing |
| `tests/test_xsh.sh` | host | 38 behavioural checks of the built-in shell |
| compile check | host | every app source, warnings treated as failures |
| `tests/terminal_tests.m` | device | 30 emulator scenarios — see [docs/TESTING.md](docs/TESTING.md) |

The terminal tests are compiled on the host but need Apple's Objective-C
runtime to execute, so they run on the phone.

---

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the pieces fit together
- [docs/TESTING.md](docs/TESTING.md) — running the on-device test suite
- [docs/ENTITLEMENTS.md](docs/ENTITLEMENTS.md) — what each entitlement buys
- [docs/ci/](docs/ci/) — a GitHub Actions workflow you can drop in

## Licence

MIT for this codebase. Termux is a trademark of the Termux project; this is an
independent implementation of the same idea for iOS.
