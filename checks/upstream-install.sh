#!/usr/bin/env bash
# shellcheck shell=bash
#
# BEHAVIOUR test for ../lib/install-upstream.sh. Sources the real file and RUNS the real function;
# nothing here is a re-implementation, and nothing here asserts about a string that a shell would
# have to interpret later. Driven from ./upstream-install.nix, which supplies a sandbox and the
# handful of tools the script shells out to.
#
# WHY THIS EXISTS AS A RUNNING TEST rather than more eval-time assertions. Every property that
# makes this delivery mode safe is a property of a running shell:
#
#   - it must not fetch anything on a machine that already has the tool. "Idempotent" asserted in
#     a comment is a wish; asserted by counting how many times curl was invoked on the second run,
#     with the network stubbed to FAIL so that even an attempt is fatal, it is a fact.
#   - an installer that exits 0 having installed nothing must fail the activation. These hosts have
#     been bitten by that class of step repeatedly, and it is precisely the case that looks fine in
#     every static reading of the code.
#   - a network failure, a 404, an HTML error page and a binary that cannot start must each be
#     distinguishable in the output an operator actually sees.
#
# HOW THE NETWORK IS STUBBED: a fake `curl` earlier on PATH than any real one, which records every
# invocation to a counter file and writes a chosen payload to whatever `-o` names. The script under
# test is not aware of it and takes no test-only argument or environment variable -- if it did, the
# thing under test would not be the thing that ships.
set -u

LIB="${1:?usage: upstream-install.sh /path/to/lib/install-upstream.sh}"
WORK="${2:?usage: upstream-install.sh <lib> <workdir>}"

# The library under test, taken from argv rather than a relative path: by the time this runs it is
# a /nix/store path, which is exactly the point -- the file that ships is the file that is tested.
# SC1091 is disabled because a runtime path is unfollowable at lint time; ./upstream-install.nix
# lints the library separately and directly, so nothing goes unchecked. (Note that a comment line
# may not START with the word this directive uses, or the linter tries to parse the prose as one.)
# shellcheck disable=SC1090,SC1091
. "$LIB"

checks=0
failures=0
CASE=""
CASEDIR=""

ok() {
  checks=$((checks + 1))
  printf '  ok    %s\n' "$1"
}

bad() {
  checks=$((checks + 1))
  failures=$((failures + 1))
  printf '  FAIL  %s\n' "$1"
  if [ -n "$CASEDIR" ]; then
    printf '        ---- stdout ----\n'
    sed 's/^/        /' "$CASEDIR/stdout" 2>/dev/null || true
    printf '        ---- stderr ----\n'
    sed 's/^/        /' "$CASEDIR/stderr" 2>/dev/null || true
    printf '        ----------------\n'
  fi
}

expect_status() {
  if [ "$2" -eq "$1" ]; then
    ok "$CASE: exits $1"
  else
    bad "$CASE: expected exit $1, got $2"
  fi
}

expect_contains() {
  if grep -qF -- "$2" "$CASEDIR/$1"; then
    ok "$CASE: $1 mentions '$2'"
  else
    bad "$CASE: $1 does not mention '$2'"
  fi
}

expect_absent() {
  if grep -qF -- "$2" "$CASEDIR/$1"; then
    bad "$CASE: $1 unexpectedly mentions '$2'"
  else
    ok "$CASE: $1 stays clear of '$2'"
  fi
}

expect_empty() {
  if [ -s "$CASEDIR/$1" ]; then
    bad "$CASE: expected $1 to be empty"
  else
    ok "$CASE: $1 is empty"
  fi
}

expect_file() {
  if [ -x "$1" ]; then
    ok "$CASE: $1 exists and is executable"
  else
    bad "$CASE: expected $1 to exist and be executable"
  fi
}

expect_no_file() {
  if [ -e "$1" ]; then
    bad "$CASE: expected $1 NOT to exist"
  else
    ok "$CASE: $1 correctly absent"
  fi
}

expect_curl_calls() {
  local actual
  actual="$(wc -l <"$CASEDIR/curl-calls" | tr -d ' ')"
  if [ "$actual" = "$1" ]; then
    ok "$CASE: curl was invoked $1 time(s)"
  else
    bad "$CASE: expected curl to be invoked $1 time(s), it was invoked $actual"
  fi
}

# A fresh $HOME and a fresh curl counter per case, so no case can pass on another's leftovers. A
# second argument names an EARLIER case whose home to reuse, which is how the idempotency case gets
# a home that already has the tool in it.
new_case() {
  CASE="$1"
  if [ -n "${2:-}" ]; then
    CASEDIR="$WORK/cases/$2"
  else
    CASEDIR="$WORK/cases/$1"
    mkdir -p "$CASEDIR/home"
  fi
  export HOME="$CASEDIR/home"
  : >"$CASEDIR/curl-calls"
  export FAKE_CURL_COUNT="$CASEDIR/curl-calls"
  export FAKE_CURL_EXIT=0
  printf '\n== %s\n' "$1"
}

# The call under test, with the arguments ../modules/home.nix renders for a real entry.
run_install() {
  status=0
  nixagent_install_upstream \
    --name testtool \
    --command tool \
    --probe .local/bin/tool \
    --url https://example.invalid/install.sh \
    --runner bash \
    "$@" \
    >"$CASEDIR/stdout" 2>"$CASEDIR/stderr" || status=$?
}

mkdir -p "$WORK/cases" "$WORK/payloads" "$WORK/fakebin"

# NO `#!/usr/bin/env` AND NO `#!/bin/sh` ANYWHERE BELOW. This runs inside a nix build sandbox,
# which has neither /usr/bin/env nor any guaranteed interpreter at a fixed path -- a generated
# script with such a shebang fails with exit 126 ("bad interpreter"), which the function under test
# then correctly but confusingly reports as "curl exited 126". Every generated script gets the
# absolute path of the bash this harness is already running under.
TEST_SH="$(command -v bash)"
export TEST_SH

# ── the fake curl ────────────────────────────────────────────────────────────────────────────
printf '#!%s\n' "$TEST_SH" >"$WORK/fakebin/curl"
cat >>"$WORK/fakebin/curl" <<'FAKECURL'
# Records the invocation, then either fails with a chosen status or writes $FAKE_PAYLOAD to
# whatever -o names. Deliberately parses -o the way real curl does rather than assuming argument
# order, so a reordering in the script under test cannot silently make this stub wrong.
set -u
out=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-o" ]; then out="$a"; fi
  prev="$a"
done
echo "curl $*" >>"$FAKE_CURL_COUNT"
if [ "${FAKE_CURL_EXIT:-0}" != "0" ]; then
  echo "curl: (${FAKE_CURL_EXIT}) The requested URL returned error: 404" >&2
  exit "${FAKE_CURL_EXIT}"
fi
cp "$FAKE_PAYLOAD" "$out"
FAKECURL
chmod +x "$WORK/fakebin/curl"
PATH="$WORK/fakebin:$PATH"
export PATH

# ── payloads: what the "downloaded installer" does when run ──────────────────────────────────
#
# Written with a `#!` line so the download-sanity check in the function under test accepts them,
# but never executed through it: the function runs each installer as `"$runner" <file>`, exactly as
# a real one is run with the interpreter its catalogue entry names. `$TEST_SH` is expanded at RUN
# time, not here, so the binaries these payloads install are runnable in the sandbox.
cat >"$WORK/payloads/good.sh" <<'PAYLOAD'
#!/bin/sh
mkdir -p "$HOME/.local/bin"
printf '#!%s\necho "tool 1.2.3"\n' "$TEST_SH" >"$HOME/.local/bin/tool"
chmod +x "$HOME/.local/bin/tool"
echo "installer: wrote $HOME/.local/bin/tool"
PAYLOAD

cat >"$WORK/payloads/records-args.sh" <<'PAYLOAD'
#!/bin/sh
printf 'args:%s\n' "$*" >"$HOME/args.txt"
mkdir -p "$HOME/.local/bin"
printf '#!%s\necho "tool 1.2.3"\n' "$TEST_SH" >"$HOME/.local/bin/tool"
chmod +x "$HOME/.local/bin/tool"
PAYLOAD

# Exits 0 having done nothing at all -- the failure these hosts have been bitten by.
cat >"$WORK/payloads/noop.sh" <<'PAYLOAD'
#!/bin/sh
echo "Setting up testtool..."
exit 0
PAYLOAD

cat >"$WORK/payloads/fails.sh" <<'PAYLOAD'
#!/bin/sh
echo "boom: could not reach the release server"
exit 3
PAYLOAD

# Installs a binary that cannot start -- exactly omp's own documented musl case.
cat >"$WORK/payloads/broken-binary.sh" <<'PAYLOAD'
#!/bin/sh
mkdir -p "$HOME/.local/bin"
printf '#!%s\necho "tool: error while loading shared libraries: libstdc++.so.6" >&2\nexit 127\n' "$TEST_SH" >"$HOME/.local/bin/tool"
chmod +x "$HOME/.local/bin/tool"
PAYLOAD

# Not a script at all: a 200 response carrying a captive-portal/CDN error page.
cat >"$WORK/payloads/error-page.html" <<'PAYLOAD'
<!DOCTYPE html>
<html><head><title>502 Bad Gateway</title></head><body>nope</body></html>
PAYLOAD

chmod +x "$WORK"/payloads/*.sh

# ── 1. it installs when the tool is absent ───────────────────────────────────────────────────
new_case installs-when-absent
export FAKE_PAYLOAD="$WORK/payloads/good.sh"
run_install
expect_status 0 "$status"
expect_curl_calls 1
expect_file "$HOME/.local/bin/tool"
expect_contains stdout "is absent -- installing from"
expect_contains stdout "installed and verified"
expect_contains stdout "tool 1.2.3"

# ── 2. THE IDEMPOTENCY GATE: a second activation must not even TRY to fetch ──────────────────
# The network is stubbed to fail outright for this run. If anything downstream of the probe ran,
# the status would be 1 and the counter would move; both staying put is the proof.
new_case idempotent-second-activation installs-when-absent
export FAKE_CURL_EXIT=22
run_install
expect_status 0 "$status"
expect_curl_calls 0
expect_empty stdout
expect_empty stderr
expect_file "$HOME/.local/bin/tool"

# ── 3. the catalogue's installer flags reach the installer ───────────────────────────────────
new_case passes-installer-args
export FAKE_PAYLOAD="$WORK/payloads/records-args.sh"
run_install -- --binary --ref v1
expect_status 0 "$status"
if [ "$(cat "$HOME/args.txt")" = "args:--binary --ref v1" ]; then
  ok "$CASE: the installer received exactly '--binary --ref v1'"
else
  bad "$CASE: installer received $(cat "$HOME/args.txt" 2>/dev/null)"
fi

# ── 4. a failed download is loud, and says which stage failed ────────────────────────────────
new_case download-failure-surfaces
export FAKE_PAYLOAD="$WORK/payloads/good.sh"
export FAKE_CURL_EXIT=22
run_install
expect_status 1 "$status"
expect_contains stderr "FAILED"
expect_contains stderr "stage:     download"
expect_contains stderr "curl exited 22"
expect_contains stderr "https://example.invalid/install.sh"
expect_contains stderr "the 'tool' command is NOT available"
expect_no_file "$HOME/.local/bin/tool"

# ── 5. a 200 that is not a script is refused BEFORE it is executed ───────────────────────────
new_case html-error-page-is-refused
export FAKE_PAYLOAD="$WORK/payloads/error-page.html"
run_install
expect_status 1 "$status"
expect_contains stderr "not a shell script"
expect_contains stderr "502 Bad Gateway"
expect_no_file "$HOME/.local/bin/tool"

# ── 6. an installer that fails carries its own output into the diagnostic ────────────────────
new_case installer-nonzero-exit
export FAKE_PAYLOAD="$WORK/payloads/fails.sh"
run_install
expect_status 1 "$status"
expect_contains stderr "stage:     install"
expect_contains stderr "the installer exited 3"
expect_contains stderr "boom: could not reach the release server"

# ── 7. THE SILENT NO-OP: exit 0 having installed nothing must NOT pass ───────────────────────
new_case exit-zero-installing-nothing-fails
export FAKE_PAYLOAD="$WORK/payloads/noop.sh"
run_install
expect_status 1 "$status"
expect_contains stderr "stage:     verify"
expect_contains stderr "exited 0 but"
expect_contains stderr ".local/bin/tool"
expect_contains stderr "Setting up testtool..."

# ── 8. installed but unable to start is also a failure ───────────────────────────────────────
new_case installed-binary-that-cannot-start
export FAKE_PAYLOAD="$WORK/payloads/broken-binary.sh"
run_install
expect_status 1 "$status"
expect_contains stderr "stage:     verify"
expect_contains stderr "cannot start"
expect_contains stderr "libstdc++.so.6"

# ── 9. warn mode is quieter, never silent ────────────────────────────────────────────────────
new_case warn-mode-does-not-abort
export FAKE_PAYLOAD="$WORK/payloads/noop.sh"
run_install --on-failure warn
expect_status 0 "$status"
expect_contains stderr "WARNING"
expect_contains stderr "onInstallFailure"
expect_contains stderr "is NOT available"
expect_absent stderr "FAILED"

# ── 10. a malformed call is a bug here and is never downgraded by warn mode ──────────────────
new_case malformed-call-is-never-downgraded
status=0
nixagent_install_upstream \
  --name testtool --command tool --probe .local/bin/tool --runner bash --on-failure warn \
  >"$CASEDIR/stdout" 2>"$CASEDIR/stderr" || status=$?
expect_status 2 "$status"
expect_contains stderr "missing required argument(s): --url"

# ── 11. the other-plane collision is reported, not resolved ──────────────────────────────────
new_case reports-a-command-already-on-path
printf '#!/bin/sh\necho "distro tool 0.9"\n' >"$WORK/fakebin/tool"
chmod +x "$WORK/fakebin/tool"
export FAKE_PAYLOAD="$WORK/payloads/good.sh"
run_install
expect_status 0 "$status"
expect_contains stderr "already resolves to"
expect_contains stderr "$WORK/fakebin/tool"
expect_file "$HOME/.local/bin/tool"
rm -f "$WORK/fakebin/tool"

printf '\n%s check(s), %s failure(s)\n' "$checks" "$failures"
if [ "$failures" -ne 0 ]; then
  echo "nixagent: upstream-install behaviour check FAILED" >&2
  exit 1
fi
