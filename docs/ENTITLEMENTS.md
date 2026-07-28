# Entitlements

`app/Termux/Resources/entitlements.plist` is what turns a normal iOS app into
something that can run a shell. TrollStore installs apps without validating
entitlements, so these are honoured.

| Entitlement | Why it is needed |
|---|---|
| `platform-application` | Marks the binary as a platform binary. Nothing below is honoured by AMFI without it. |
| `com.apple.private.security.no-sandbox` | Leaves the app sandbox. This is the one that makes `posix_spawn()` work; without it, spawning fails with `EPERM`. |
| `com.apple.private.security.storage.AppDataContainers` | `platform-application` tightens container access as a side effect; this restores access to the app's own `Documents/`, where `$PREFIX` lives. |
| `com.apple.private.persona-mgmt` | Allows spawning under a different persona — needed for root helpers. |
| `dynamic-codesigning` | Lets downloaded binaries execute, which is the entire point of `apt install`. |
| `com.apple.developer.kernel.increased-memory-limit`, `...extended-virtual-addressing`, `com.apple.private.memorystatus` | Raise the jetsam ceiling so a big compile is not killed mid-build. |
| `com.apple.security.exception.files.absolute-path.read-write` | Filesystem access outside the container. |
| `com.apple.developer.networking.multipath` | Keeps networking usable in the background so long downloads survive. |

## Side effects to know about

`platform-application` **tightens** some sandbox rules even as it unlocks
others. Most notably, every IOKit user client class you want to touch needs
its own exception entitlement. This app does not use IOKit, so it does not
come up here — but it will bite if you extend it.

## Verifying what actually got signed

```bash
python3 tools/verify_signature.py build/Payload/Termux.app/Termux
```

Prints the CodeDirectory, checks all page hashes, and dumps the decoded
entitlements. Expect `RESULT: PASS` and all ten entitlements listed.

## DER entitlements

Since iOS 15, AMFI wants entitlements in DER (ASN.1) form in addition to the
XML plist. A binary carrying only XML entitlements may have them silently
ignored — which looks like "TrollStore installed it but spawning still fails".

`tools/fakesign.py` emits both, in slots 5 (XML) and 7 (DER). The DER encoder
lives in the same file and is covered by unit tests.

## If spawning fails on device

The terminal prints the `posix_spawn` error. Common causes:

- **`EPERM`** — the app was installed without TrollStore, or the signature was
  replaced. Reinstall the `.ipa` through TrollStore.
- **`ENOENT`** — the shell path does not exist. Expected before a bootstrap is
  installed if the bundled `xsh` is missing from the bundle; check that
  `Payload/Termux.app/xsh` is present in the `.ipa`.
- **`EACCES`** — the target is not executable. The bootstrap installer
  `chmod +x`es everything under `bin/`, `sbin/`, `usr/bin`, `usr/sbin` and
  `libexec` for exactly this reason.
