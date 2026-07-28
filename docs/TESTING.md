# Testing

```bash
make test
```

runs everything that can be verified on a Linux host:

| Suite | What it checks |
|---|---|
| `tests/test_fakesign.py` | 15 unit tests: DER encoding, superblob layout, page hashes, idempotent re-signing, header-slack handling |
| `tests/test_xsh.sh` | 38 behavioural checks of the built-in shell, actually executed |
| compile check | all 12 app sources compile clean for arm64 iOS; warnings fail the run |
| end-to-end | `make ipa` succeeds and the resulting signature verifies |

## The terminal test suite

`tests/terminal_tests.m` contains 30 scenarios covering the escape sequence
parser: cursor movement, scrolling regions, SGR and truecolour, UTF-8 split
across reads, wide characters, deferred wrap, insert/delete, the alternate
screen, mouse modes, OSC titles, and device status reports.

These compile on the host but need Apple's Objective-C runtime to *run*, which
Linux does not have. `make test` therefore compiles them as a correctness gate
and leaves execution to the device.

### Running them on the phone

Build the test binary and put it in the bundle:

```bash
SDK=.toolchain/sdks/iPhoneOS16.5.sdk
.toolchain/zig/zig cc -target aarch64-ios.14.0 \
  -isysroot $SDK -I$SDK/usr/include \
  -F$SDK/System/Library/Frameworks -L$SDK/usr/lib \
  -Iapp/Termux/Terminal -fobjc-arc \
  -Wno-nullability-completeness -Wno-macro-redefined \
  -Wl,-headerpad,0x1000 -framework Foundation \
  -o build/Payload/Termux.app/terminal-tests \
  tests/terminal_tests.m \
  app/Termux/Terminal/TXTerminalBuffer.m \
  app/Termux/Terminal/TXTerminalEmulator.m

python3 tools/fakesign.py build/Payload/Termux.app/terminal-tests \
  -e app/Termux/Resources/entitlements.plist -i dev.termux.ios.tests

cd build && rm -f Termux.ipa && zip -qr Termux.ipa Payload
```

Install, then from inside Termux:

```sh
$(dirname $(which xsh 2>/dev/null || echo /var/containers))/terminal-tests
```

or more simply, since the app bundle is on `$PATH`-adjacent territory, find it
with:

```sh
ls /private/var/containers/Bundle/Application/*/Termux.app/terminal-tests
```

Expected output ends with:

```
NNN checks, 0 failures
```

Any failure prints the sequence under test, the expected screen contents and
what was actually produced.

## Adding tests

**Signer** — add to `tests/test_fakesign.py`. The `SigningTests` class builds a
real arm64 Mach-O with the cross toolchain and signs it, so tests there
exercise the actual code path rather than a mock.

**Shell** — add a `check` line to `tests/test_xsh.sh`:

```bash
check "description" "expected stdout" 'script to run'
check_status "description" "expected exit code" 'script to run'
```

**Terminal** — add a `TestSomething()` function to `tests/terminal_tests.m` and
call it from `main()`. Use `Feed(terminal, @"\033[...")` to push escape
sequences and the `Check*` helpers to assert.

## Continuous integration

A ready-to-use GitHub Actions workflow is provided at `docs/ci/build.yml`. It
caches the toolchain, runs the host suite, builds the `.ipa` and uploads it as
an artifact. See `docs/ci/README.md` for how to enable it.
