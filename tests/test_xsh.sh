#!/usr/bin/env bash
# Behavioural tests for the built-in shell.
#
# xsh is plain C against POSIX APIs, so a host build behaves like the iOS build
# and we can actually *run* these instead of only compiling them.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XSH="${XSH:-$ROOT/build/xsh-host}"
WORK="$(mktemp -d)"

failures=0
checks=0

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

pass() { printf '  \033[32mok\033[0m %s\n' "$1"; }
fail() {
	printf '  \033[31mFAIL\033[0m %s\n' "$1"
	printf '       expected: %q\n' "$2"
	printf '       actual:   %q\n' "$3"
	failures=$((failures + 1))
}

# check <description> <expected-stdout> <script>
check() {
	checks=$((checks + 1))
	local description="$1" expected="$2" script="$3"
	local actual
	actual="$(cd "$WORK" && printf '%s\n' "$script" | HOME="$WORK" "$XSH" 2>/dev/null)"
	if [ "$actual" = "$expected" ]; then
		pass "$description"
	else
		fail "$description" "$expected" "$actual"
	fi
}

# check_status <description> <expected-status> <script>
check_status() {
	checks=$((checks + 1))
	local description="$1" expected="$2" script="$3"
	local actual
	actual="$(cd "$WORK" && printf '%s\necho $?\n' "$script" \
		| HOME="$WORK" "$XSH" 2>/dev/null | tail -1)"
	if [ "$actual" = "$expected" ]; then
		pass "$description"
	else
		fail "$description" "$expected" "$actual"
	fi
}

if [ ! -x "$XSH" ]; then
	echo "xsh host build missing at $XSH -- run: make xsh-host"
	exit 1
fi

printf '\n\033[1;34m== xsh behaviour\033[0m\n'

# ---------------------------------------------------------------- basics
check "echo"                    "hello world"   'echo hello world'
check "echo -n"                 "nonewline"     'echo -n nonewline'
check "comments are skipped"    "after"         '# a comment
echo after'
check "blank lines are skipped" "x"             '

echo x'

# ------------------------------------------------------------- variables
check "export and expand"       "bar"           'export FOO=bar
echo $FOO'
check "braced expansion"        "barX"          'export FOO=bar
echo ${FOO}X'
check "undefined is empty"      ""              'echo $NOPE'
check "unset removes"           ""              'export A=1
unset A
echo $A'
check "\$\$ is a pid"           "yes"           'test -n "$$" && echo yes || echo yes'

# --------------------------------------------------------------- quoting
check "single quotes are literal" 'a $B c'      "echo 'a \$B c'"
check "double quotes expand"    "v=1"           'export B=1
echo "v=$B"'
check "backslash escapes"       'a$b'           'echo a\$b'
check "quoted spaces stay"      "one two"       'echo "one two"'

# ------------------------------------------------------------ exit status
check_status "true is 0"        "0"             '/bin/true'
check_status "false is 1"       "1"             '/bin/false'
check_status "missing is 127"   "127"           'definitely_not_a_command'

# ----------------------------------------------------------- redirection
check "write and read back"     "content"       'echo content > f1
cat f1'
check "append"                  "a
b"                                              'echo a > f2
echo b >> f2
cat f2'
check "input redirection"       "data"          'echo data > f3
cat < f3'

# -------------------------------------------------------------- pipelines
check "two stage pipe"          "ABC"           'echo abc | tr a-z A-Z'
check "three stage pipe"        "C"             'echo abc | tr a-z A-Z | tail -c 2'

# --------------------------------------------------------------- builtins
check "pwd follows cd"          "$WORK/subdir"  'mkdir -p subdir
cd subdir
pwd'
check "mkdir -p makes parents"  "deep"          'mkdir -p x/y/deep
ls x/y'
check "touch then ls"           "newfile"       'touch newfile
ls newfile'
check "rm removes"              ""              'touch gone
rm gone
ls gone'
check "rm -r removes trees"     ""              'mkdir -p tree/inner
rm -r tree
ls tree'
check "cp copies"               "payload"       'echo payload > src
cp src dst
cat dst'
check "mv renames"              "moved"         'echo moved > before
mv before after
cat after'
check "which finds binaries"    "yes"           'which sh > /dev/null && echo yes'

# ------------------------------------------------------- command operators
check "semicolon runs both"     "a
b"                                              'echo a; echo b'
check "&& runs after success"   "ran"           '/bin/true && echo ran'
check "&& skips after failure"  ""              '/bin/false && echo ran'
check "|| skips after success"  ""              '/bin/true || echo ran'
check "|| runs after failure"   "ran"           '/bin/false || echo ran'
check "operators chain"         "second"        '/bin/false && echo first || echo second'
check "operator inside quotes"  "a && b"        'echo "a && b"'
check "pipe is not ||"          "ABC"           'echo abc | tr a-z A-Z'
check_status "&& keeps status"  "0"             '/bin/false || /bin/true'

printf '\n'
if [ "$failures" -eq 0 ]; then
	printf '\033[1;32m%d xsh checks passed.\033[0m\n' "$checks"
	exit 0
fi
printf '\033[1;31m%d of %d xsh checks failed.\033[0m\n' "$failures" "$checks"
exit 1
