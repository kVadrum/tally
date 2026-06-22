#!/usr/bin/env bash
# Behavioral test suite for tally. No framework: each check asserts an
# observable (a number from --json, an exit code, a substring of text
# output). Run: tests/run.sh
#
# The load-bearing assertion is the token DEDUP regression. basic.jsonl
# repeats each assistant message id across its content-block lines, all
# carrying the same usage — exactly how Claude Code logs. The naive sum of
# output tokens is 340; the correct, deduped sum is 130. If anyone breaks
# the group-by-message-id, that assertion fails loudly.

set -u
cd "$(dirname "$0")/.."
BIN="./bin/tally"
FIX="tests/fixtures"

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }

# eq NAME EXPECTED ACTUAL
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi; }
# contains NAME HAYSTACK NEEDLE
contains() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing [$3])" ;; esac; }
# notcontains NAME HAYSTACK NEEDLE
notcontains() { case "$2" in *"$3"*) bad "$1 (unexpected [$3])" ;; *) ok "$1" ;; esac; }
# exitcode NAME EXPECTED -- cmd...
exitcode() { local n="$1" want="$2"; shift 3; "$@" >/dev/null 2>&1; eq "$n" "$want" "$?"; }

J() { "$BIN" --json "$1" | jq -r "$2"; }  # field from single-file json

echo "tally test suite"
echo

# --- dedup regression + core accounting on basic.jsonl --------------------
eq "basic: turns deduped"       "2"   "$(J $FIX/basic.jsonl '.turns')"
eq "basic: output deduped (130 not 340)" "130" "$(J $FIX/basic.jsonl '.output')"
eq "basic: input deduped"       "300" "$(J $FIX/basic.jsonl '.input')"
eq "basic: cache_read deduped"  "3000" "$(J $FIX/basic.jsonl '.cache_read')"
eq "basic: cache_write deduped" "200" "$(J $FIX/basic.jsonl '.cache_write')"
eq "basic: ntools"              "3"   "$(J $FIX/basic.jsonl '.ntools')"
eq "basic: prompts (string only)" "1" "$(J $FIX/basic.jsonl '.prompts')"
eq "basic: elapsed_s from stamps" "30" "$(J $FIX/basic.jsonl '.elapsed_s')"
eq "basic: Bash counted across blocks" "2" "$(J $FIX/basic.jsonl '.tool_counts[] | select(.name=="Bash") | .n')"
eq "basic: Read counted"        "1"   "$(J $FIX/basic.jsonl '.tool_counts[] | select(.name=="Read") | .n')"
eq "basic: single model"        "claude-opus-4-8" "$(J $FIX/basic.jsonl '.models | join(",")')"
eq "basic: branch"              "main" "$(J $FIX/basic.jsonl '.branch')"

# --- text rendering -------------------------------------------------------
TXT="$($BIN --no-color $FIX/basic.jsonl)"
contains "text: deduped out token" "$TXT" "out 130"
contains "text: short session id"  "$TXT" "sess-bas"
contains "text: cwd basename"      "$TXT" "proj"
contains "text: tool breakdown"    "$TXT" "Bash 2"
notcontains "text: --no-color has no ESC" "$TXT" $'\033'

# --- multimodel -----------------------------------------------------------
eq "multimodel: two models" "2" "$(J $FIX/multimodel.jsonl '.models | length')"

# --- noassist (prompt, no assistant response) -----------------------------
eq "noassist: zero turns"   "0" "$(J $FIX/noassist.jsonl '.turns')"
eq "noassist: one prompt"   "1" "$(J $FIX/noassist.jsonl '.prompts')"
eq "noassist: no models"    "0" "$(J $FIX/noassist.jsonl '.models | length')"
eq "noassist: zero output"  "0" "$(J $FIX/noassist.jsonl '.output')"
exitcode "noassist: still a valid session (exit 0)" 0 -- $BIN $FIX/noassist.jsonl

# --- error paths ----------------------------------------------------------
exitcode "empty transcript -> exit 2" 2 -- $BIN $FIX/empty.jsonl
exitcode "invalid json    -> exit 2"  2 -- $BIN $FIX/bad.jsonl
exitcode "missing file    -> exit 2"  2 -- $BIN $FIX/does-not-exist.jsonl
exitcode "unknown option  -> exit 2"  2 -- $BIN --nope $FIX/basic.jsonl
exitcode "--version       -> exit 0"  0 -- $BIN --version
exitcode "--help          -> exit 0"  0 -- $BIN --help

# --- directory mode -------------------------------------------------------
DIR_OUT="$($BIN --no-color $FIX 2>/dev/null)"
contains "dir: prints TOTAL line" "$DIR_OUT" "TOTAL"
DIR_ERR="$($BIN --no-color $FIX 2>&1 >/dev/null)"
contains "dir: warns on skipped transcript" "$DIR_ERR" "skipping"
exitcode "dir: exit 0 despite skips" 0 -- $BIN $FIX

# readable sessions = basic + multimodel + noassist (empty & bad skipped)
DJSON="$($BIN --json $FIX 2>/dev/null)"
eq "dir json: 3 readable sessions" "3" "$(jq '.total.sessions' <<<"$DJSON")"
eq "dir json: total output 160"    "160" "$(jq '.total.output' <<<"$DJSON")"
eq "dir json: total turns 4"       "4"   "$(jq '.total.turns' <<<"$DJSON")"
eq "dir json: sorted by started"   "sess-basic" "$(jq -r '.sessions[0].session' <<<"$DJSON")"

# --- quiet ----------------------------------------------------------------
QOUT="$($BIN --no-color --quiet $FIX 2>/dev/null)"
contains "quiet: keeps TOTAL"      "$QOUT" "TOTAL"
notcontains "quiet: drops table header" "$QOUT" "OUTPUT-TOK"

echo
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
