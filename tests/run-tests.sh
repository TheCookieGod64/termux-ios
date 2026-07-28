#!/usr/bin/env bash
# Runs everything that can be checked on the build host.
#
#   1. python unit tests for the code signer
#   2. a compile check of every app source for arm64 iOS
#   3. a compile check of the Objective-C terminal tests
#      (they are *run* on the device -- see docs/TESTING.md -- because Linux
#      has no Apple Objective-C runtime)
#   4. end-to-end: build the ipa and verify its signature

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TC="$ROOT/.toolchain"
ZIG="$TC/zig/zig"

pick_sdk() {
	local best=""
	local best_version=0
	for candidate in "$TC"/sdks/iPhoneOS*.sdk; do
		[ -d "$candidate" ] || continue
		local version
		version="$(basename "$candidate" | sed 's/iPhoneOS//; s/\.sdk//')"
		local numeric
		numeric="$(echo "$version" | awk -F. '{printf "%d%03d", $1, $2}')"
		if [ "$numeric" -gt "$best_version" ]; then
			best_version="$numeric"
			best="$candidate"
		fi
	done
	echo "$best"
}

SDK="$(pick_sdk)"

failures=0
section() { printf '\n\033[1;34m== %s\033[0m\n' "$1"; }
pass() { printf '  \033[32mok\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; failures=$((failures + 1)); }

# ---------------------------------------------------------------- 1. signer
section "code signer unit tests"
signer_log="$(mktemp)"
if python3 tests/test_fakesign.py >"$signer_log" 2>&1; then
	pass "tools/fakesign.py ($(grep -oE "Ran [0-9]+ tests" "$signer_log") )"
else
	tail -25 "$signer_log"
	fail "tools/fakesign.py"
fi
rm -f "$signer_log"

# ------------------------------------------------------------- 2. xsh shell
section "built-in shell behaviour"
mkdir -p build
if cc -O2 -Wall -Wextra -Wno-unused-parameter -o build/xsh-host native/xsh/xsh.c 2>/dev/null; then
	xsh_log="$(mktemp)"
	if XSH="$ROOT/build/xsh-host" bash tests/test_xsh.sh >"$xsh_log" 2>&1; then
		pass "$(grep -oE "[0-9]+ xsh checks passed" "$xsh_log")"
	else
		grep -E "FAIL|expected|actual" "$xsh_log" | head -20
		fail "tests/test_xsh.sh"
	fi
	rm -f "$xsh_log"
else
	cc -O2 -Wall -Wextra -o build/xsh-host native/xsh/xsh.c 2>&1 | head -10
	fail "xsh host build"
fi

if [ ! -x "$ZIG" ] || [ -z "$SDK" ]; then
	printf '\n\033[33mSkipping compile checks -- run "make toolchain" first.\033[0m\n'
	exit $((failures > 0))
fi

CFLAGS=(-target aarch64-ios.14.0 -isysroot "$SDK" -I"$SDK/usr/include"
        -F"$SDK/System/Library/Frameworks" -L"$SDK/usr/lib"
        -Iapp/Termux -Iapp/Termux/Terminal -Iapp/Termux/Session
        -Iapp/Termux/UI -Iapp/Termux/Bootstrap
        -fobjc-arc -Wall -Wextra -Wno-unused-parameter
        -Wno-nullability-completeness -Wno-macro-redefined
        -Wno-unknown-warning-option -Wno-deprecated-declarations)

# ------------------------------------------------------- 2. app compilation
section "compiling app sources for arm64 iOS"
for source in $(find app/Termux -name '*.m' | sort); do
	output="$("$ZIG" cc "${CFLAGS[@]}" -c "$source" -o /dev/null 2>&1 \
		| grep -E "error|warning:" \
		| grep -v "nullability\|objc-load-method\|unguarded-availability" || true)"
	if [ -n "$output" ]; then
		echo "$output" | head -5
		fail "$source"
	else
		pass "$source"
	fi
done

# --------------------------------------------------- 3. terminal test suite
section "compiling terminal tests"
if "$ZIG" cc "${CFLAGS[@]}" -Wl,-undefined,dynamic_lookup \
	-framework Foundation \
	-o build/terminal-tests \
	tests/terminal_tests.m \
	app/Termux/Terminal/TXTerminalBuffer.m \
	app/Termux/Terminal/TXTerminalEmulator.m 2>/dev/null; then
	pass "tests/terminal_tests.m (run it on device: see docs/TESTING.md)"
else
	"$ZIG" cc "${CFLAGS[@]}" -Wl,-undefined,dynamic_lookup -framework Foundation \
		-o build/terminal-tests tests/terminal_tests.m \
		app/Termux/Terminal/TXTerminalBuffer.m \
		app/Termux/Terminal/TXTerminalEmulator.m 2>&1 \
		| grep -E "error" | head -10
	fail "tests/terminal_tests.m"
fi

# ------------------------------------------------------------ 4. end to end
section "end-to-end build"
if make ipa >/dev/null 2>&1; then
	pass "make ipa"
	if python3 tools/verify_signature.py build/Payload/Termux.app/Termux 2>&1 \
		| grep -q "^RESULT: PASS"; then
		pass "signature verifies"
	else
		python3 tools/verify_signature.py build/Payload/Termux.app/Termux | tail -20
		fail "signature verification"
	fi
else
	make ipa 2>&1 | tail -15
	fail "make ipa"
fi

printf '\n'
if [ "$failures" -eq 0 ]; then
	printf '\033[1;32mAll checks passed.\033[0m\n'
	exit 0
fi
printf '\033[1;31m%d check(s) failed.\033[0m\n' "$failures"
exit 1
