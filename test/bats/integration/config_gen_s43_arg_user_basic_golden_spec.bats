#!/usr/bin/env bats
#
# config_gen_s43_arg_user_basic_golden_spec.bats -- the s43 arg_user
# (migration 7) basic corpus (bare / alias_root / unrelated) against the
# .dockerfile / .files / .events goldens (base#2348, S43n-1 of base#2074).
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

# why: a bare ARG USER is warned about (line 5) after a literal-default one (line 2).
@test "s43 arg_user golden: bare" {
  run _check_case bare
  assert_success
}

# why: two ARG USER="${USER_NAME}" aliases are each warned about as may-run-as-root.
@test "s43 arg_user golden: alias_root" {
  run _check_case alias_root
  assert_success
}

# why: ARG USERLAND / ARG USER_NAME are not ARG USER; no warning.
@test "s43 arg_user golden: unrelated" {
  run _check_case unrelated
  assert_success
}

# ── literal expectations, independent of the goldens ────────────────────────

# why: the issue gives the bare events as literals; pin them so a wrong golden
# cannot pass by being regenerated the same way.
@test "s43 arg_user golden: bare events golden equals the issue's literal events" {
  local _port='manual port: in sys declare ARG USER_NAME / USER_GROUP / USER_UID / USER_GID and create the user from them (dist/dockerfile/Dockerfile:214, :298), then in each later stage alias ARG USER="${USER_NAME}" (dist/dockerfile/Dockerfile:329)'
  run cat "${GOLDEN}/s43_arg_user_bare.events"
  assert_success
  assert_output "$(printf '%s\n%s\n%s' \
    $'dockerfile_unchanged\t  Dockerfile unchanged: Dockerfile:2: ARG USER defaults to "initial" and compose passes no USER build arg -- the image builds that user, not the one compose passes, unless the build is given --build-arg USER; '"${_port}"' (base#1348)' \
    $'dockerfile_unchanged\t  Dockerfile unchanged: Dockerfile:5: ARG USER has no default and compose passes no USER build arg -- unless a parent stage declares ARG USER (which this stage then inherits), the image does not get the user compose passes; '"${_port}"' (base#1322)' \
    $'dockerfile_migrations_reported\t  Dockerfile migrations: 1 of 1 matched (arg_user), 0 file(s) rewritten\tmatched=1\tavailable=1\tnames=arg_user\trewritten=0')"
}

# why: the unrelated case has no warning, only the report event.
@test "s43 arg_user golden: unrelated events golden is the single none-matched report" {
  run cat "${GOLDEN}/s43_arg_user_unrelated.events"
  assert_success
  assert_output $'dockerfile_migrations_reported\t  Dockerfile migrations: 0 of 1 matched (none), 0 file(s) rewritten\tmatched=0\tavailable=1\tnames=none\trewritten=0'
}

# why: arg_user only reports, never rewrites: dockerfile golden == fixture, .files empty.
@test "s43 arg_user golden: dockerfile goldens equal their fixtures and files goldens are 0 bytes" {
  local _c
  for _c in bare alias_root unrelated; do
    cmp -- "${CORPUS}/s43_arg_user_${_c}.Dockerfile" "${GOLDEN}/s43_arg_user_${_c}.dockerfile"
    [[ -f "${GOLDEN}/s43_arg_user_${_c}.files" ]]
    [[ ! -s "${GOLDEN}/s43_arg_user_${_c}.files" ]]
  done
}

# ── the partition check ─────────────────────────────────────────────────────

# why: each case has exactly one fixture and exactly three goldens.
@test "s43 arg_user golden: every case has one fixture and exactly its three goldens" {
  run _check_partition bare alias_root unrelated
  assert_success
}
