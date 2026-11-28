#!/usr/bin/env bats
#
# config_gen_s43_arg_user_continuation_golden_spec.bats -- the s43 arg_user
# (migration 7) continuation corpus (continuation / multiname /
# escape_directive) against the .dockerfile / .files / .events goldens
# (base#2350, S43n-3 of base#2074).
#
# why: before any Go migration exists, the shell apply_migrations with
# _MIGRATIONS=( arg_user ) is the oracle; the Go side must match byte for
# byte. Shared generator: s43_arg_user_helper.bash.

bats_require_minimum_version 1.5.0

setup() {
  export LOG_FORMAT=text
  load "${BATS_TEST_DIRNAME}/../unit/test_helper"
  load "${BATS_TEST_DIRNAME}/s43_arg_user_helper"
}

# ── one test per case ───────────────────────────────────────────────────────

# why: a backslash continuation around ARG USER warns at lines 4 (bare) and 7 (root).
@test "s43 arg_user golden: continuation" {
  run _check_case continuation
  assert_success
}

# why: continued declarations and USER as a later name in a multi-name ARG
#      each warn at the line the ARG instruction starts on.
@test "s43 arg_user golden: multiname" {
  run _check_case multiname
  assert_success
}

# why: a "# escape=`" directive moves the continuation character; an unclosed
#      quote in the default is unreadable and gets the may-run-as-root notice.
@test "s43 arg_user golden: escape_directive" {
  run _check_case escape_directive
  assert_success
}

# ── literal expectations, independent of the goldens ────────────────────────

# why: the issue gives the continuation events as literals; pin them so a wrong
# golden cannot pass by being regenerated the same way.
@test "s43 arg_user golden: continuation events golden equals the issue's literal events" {
  local _port='manual port: in sys declare ARG USER_NAME / USER_GROUP / USER_UID / USER_GID and create the user from them (dist/dockerfile/Dockerfile:214, :298), then in each later stage alias ARG USER="${USER_NAME}" (dist/dockerfile/Dockerfile:329)'
  run cat "${GOLDEN}/s43_arg_user_continuation.events"
  assert_success
  assert_output "$(printf '%s\n%s\n%s' \
    $'dockerfile_unchanged\t  Dockerfile unchanged: Dockerfile:4: ARG USER has no default and compose passes no USER build arg -- unless a parent stage declares ARG USER (which this stage then inherits), the image does not get the user compose passes; '"${_port}"' (base#1322)' \
    $'dockerfile_unchanged\t  Dockerfile unchanged: Dockerfile:7: ARG USER defaults to USER_NAME (an earlier upgrade'\''s rewrite) or could not be read -- if sys never declares USER_NAME and creates the user from it, the image may run as root; '"${_port}"' (base#1322)' \
    $'dockerfile_migrations_reported\t  Dockerfile migrations: 1 of 1 matched (arg_user), 0 file(s) rewritten\tmatched=1\tavailable=1\tnames=arg_user\trewritten=0')"
}

# why: arg_user only reports, never rewrites: dockerfile golden == fixture, .files empty.
@test "s43 arg_user golden: dockerfile goldens equal their fixtures and files goldens are 0 bytes" {
  local _c
  for _c in continuation multiname escape_directive; do
    cmp -- "${CORPUS}/s43_arg_user_${_c}.Dockerfile" "${GOLDEN}/s43_arg_user_${_c}.dockerfile"
    [[ -f "${GOLDEN}/s43_arg_user_${_c}.files" ]]
    [[ ! -s "${GOLDEN}/s43_arg_user_${_c}.files" ]]
  done
}

# ── the partition check ─────────────────────────────────────────────────────

# why: each case has exactly one fixture and exactly three goldens.
@test "s43 arg_user golden: every case has one fixture and exactly its three goldens" {
  run _check_partition continuation multiname escape_directive
  assert_success
}
