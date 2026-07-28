# Continuous integration

`build.yml` is a ready-to-use GitHub Actions workflow: it caches the cross
toolchain, runs the host test suite, builds the `.ipa` and uploads it as an
artifact on every push.

It lives here rather than in `.github/workflows/` because the bot that opened
this branch is not permitted to create workflow files. To enable it:

```bash
mkdir -p .github/workflows
git mv docs/ci/build.yml .github/workflows/build.yml
git commit -m "Enable CI"
```

The first run takes a while (it downloads the iOS SDKs); subsequent runs hit
the cache.
