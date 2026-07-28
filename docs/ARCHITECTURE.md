# Architecture

## The data path

```
  keyboard / extra keys                        pty master
          │                                         │
          ▼                                         ▼
   TXTerminalView ──► TXTerminalSession ──► TXPTYSession ──► shell process
          ▲                    │                              (bash, vim, ...)
          │                    ▼
          └────────── TXTerminalEmulator ◄── bytes read from the pty
                             │
                             ▼
                      TXTerminalBuffer
```

Input flows down the left, output up the right. Nothing blocks the main thread:
the pty is drained on a serial dispatch queue and hands `NSData` to the
emulator on the main queue, which parses it into the buffer; the view redraws
at most once per display refresh.

## Components

### TXTerminalBuffer

The screen as a grid of `TXCell` values plus a scrollback ring.

Lines are individually heap-allocated (`TXLine *`), so scrolling is a pointer
shuffle instead of a `memmove` of the whole grid — the difference is visible
when something spews output.

Each cell carries its codepoint, foreground, background, attribute flags, and
an index into a combining-mark table (marks are stored out-of-band so the cell
stays 16 bytes).

Every mutation bumps a generation counter and stamps the line, so the view can
ask "did this row change since I last drew it?" without diffing.

Resizing preserves content: shrinking pushes top lines into scrollback,
growing pulls them back out.

### TXTerminalEmulator

A state machine following the DEC parser model: `Ground`, `Escape`,
`CSIEntry/Param/Intermediate/Ignore`, `OSCString`, `DCS*`. C0 controls are
handled out-of-band from nearly any state, matching real terminals.

Details that matter for compatibility:

- **Deferred wrap.** Writing to the last column leaves the cursor there with a
  pending-wrap flag; the wrap happens when the *next* glyph arrives. Without
  this, editors put line breaks in the wrong place.
- **Erase colour.** Cleared cells keep the current background but not the
  foreground, which is what ANSI specifies and what `clear` relies on.
- **Wide glyphs.** A double-width character occupies two cells; the second is
  flagged `TXCellFlagWideTrailer` and never drawn on its own.
- **UTF-8 across reads.** Decoder state persists between `parseData:` calls, so
  a multi-byte sequence split across two pty reads still decodes.
- **Zero/default parameters.** Per ECMA-48 an omitted or zero parameter means
  the sequence's default.

### TXPTYSession

`openpty()` for the pty pair, then `posix_spawn` with:

- `POSIX_SPAWN_SETSID` — the child leads a new session, making the pty its
  controlling terminal, which is what gives you working job control and `^C`
- `POSIX_SPAWN_CLOEXEC_DEFAULT` — nothing leaks into the child but the three
  standard descriptors
- all signals reset to their default disposition

`fork()` is deliberately avoided: it is unreliable on iOS because the child
inherits state the frameworks assume is single-threaded.

Signals go to the *foreground process group* (`tcgetpgrp`), not the shell, so
`^C` interrupts the running command rather than killing your session.

`posix_spawn_file_actions_addchdir_np` exists in libSystem but is marked
unavailable in the SDK headers; it is resolved with `dlsym` at runtime, with a
`chdir`-around-the-spawn fallback.

### TXBootstrap

Owns the userland layout:

```
<container>/Documents/prefix/     $PREFIX  (bin, lib, etc, usr, var, tmp)
<container>/Documents/home/       $HOME
```

Everything lives under `Documents/` so it survives app updates and is
reachable from the Files app.

Because `/` is not writable, the apt/dpkg configuration redirects every path
into `$PREFIX` (`Dir`, `Dir::State`, `Dir::Cache`, `--root`, `--admindir`) and
sets the architecture to `iphoneos-arm64`.

### TXArchive

A streaming tar reader, because iOS has no libarchive and no `tar` binary
before the bootstrap exists. Handles ustar and GNU tar, long names (`L`/`K`),
PAX extended headers, symlinks, hardlinks, and gzip via zlib from libSystem.

Entries that would escape the destination directory are rejected. Links are
applied after all files, since a link's target may appear later in the
archive.

### TXTerminalView

Draws with CoreText in two passes per row: background runs first, then glyph
runs. Cells sharing a style are coalesced into a single `CTLine`, so a line of
uniform text is one draw call rather than eighty.

Redraws are coalesced through a `CADisplayLink` — the emulator only sets a
dirty flag, so a program printing thousands of lines a second still renders at
the display's refresh rate instead of once per write.

### xsh

The bundled shell (`native/xsh/xsh.c`), plain C against POSIX APIs. It exists
so the app is useful the moment it launches, and as a rescue shell if a
bootstrap gets broken.

Because it is portable C, it builds for the host too, which is how
`tests/test_xsh.sh` can actually execute its 38 checks rather than only
compiling them.

## Build pipeline

```
   app/Termux/**.m ─┐
                    ├─► zig cc (clang, -target aarch64-ios) ─┐
   native/xsh/*.c ──┘                                        │
                                                             ▼
                            tools/fakesign.py  ◄── entitlements.plist
                                    │
                                    ▼
                     Payload/Termux.app ──► zip ──► Termux.ipa
```

`-Wl,-headerpad,0x1000` is passed at link time to reserve room in the Mach-O
header for the `LC_CODE_SIGNATURE` load command the signer adds afterwards.

### The signer

`tools/fakesign.py` writes an embedded signature superblob containing:

| Blob | Purpose |
|---|---|
| CodeDirectory (SHA-256) | page hashes + special slot hashes |
| Requirements | empty, but its hash must be present |
| Entitlements (XML) | what you asked for |
| DER entitlements | the same, ASN.1 encoded — AMFI needs this on iOS 15+ |
| CMS wrapper | empty: ad-hoc signatures carry no certificate |

Two bugs worth remembering, both now covered by regression tests:

1. The SuperBlob header is **12** bytes (magic, length, count) before the
   index — not 8. Getting this wrong produces garbage blob offsets.
2. Zerofill sections (`__bss`) report `fileoff = 0` while having non-zero
   size, so they must be excluded when computing free header space.
