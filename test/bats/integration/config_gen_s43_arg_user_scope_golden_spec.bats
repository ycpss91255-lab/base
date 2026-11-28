#!/usr/bin/env bats
#
# config_gen_s43_arg_user_scope_golden_spec.bats -- the s43 arg_user
# (migration 7) scope / default-spelling corpus (parent_inherit / case_from /
# global_user_name / sibling_stage / inherited_stage / decl_order / quoting)
# against the .dockerfile / .files / .events goldens (base#2349, S43n-2 of
# base#2074).
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

# why: a bare ARG USER in a stage whose parent declares none, after a
# USER_NAME-default one.
@test "s43 arg_user golden: parent_inherit" {
  run _check_case parent_inherit
  assert_success
}

# why: lower-case `from` still opens a stage.
@test "s43 arg_user golden: case_from" {
  run _check_case case_from
  assert_success
}

# why: a global (pre-FROM) ARG USER_NAME changes which stage lines are warned.
@test "s43 arg_user golden: global_user_name" {
  run _check_case global_user_name
  assert_success
}

# why: a sibling stage's ARG USER does not leak into this stage.
@test "s43 arg_user golden: sibling_stage" {
  run _check_case sibling_stage
  assert_success
}

# why: a stage inheriting from a stage that declares ARG USER.
@test "s43 arg_user golden: inherited_stage" {
  run _check_case inherited_stage
  assert_success
}

# why: declaration order of USER_NAME vs ARG USER.
@test "s43 arg_user golden: decl_order" {
  run _check_case decl_order
  assert_success
}

# why: quoting variants of the USER_NAME default.
@test "s43 arg_user golden: quoting" {
  run _check_case quoting
  assert_success
}

# ── literal expectation, independent of the goldens ─────────────────────────

# why: the issue gives parent_inherit's warnings as 4:root 6:bare; pin the
# events as literals so a wrong golden cannot pass by being regenerated the
# same way.
@test "s43 arg_user golden: parent_inherit events golden equals the issue's literal events" {
  local _port='manual port: in sys declare ARG USER_NAME / USER_GROUP / USER_UID / USER_GID and create the user from them (dist/dockerfile/Dockerfile:214, :298), then in each later stage alias ARG USER="${USER_NAME}" (dist/dockerfile/Dockerfile:329)'
  run cat "${GOLDEN}/s43_arg_user_parent_inherit.events"
  assert_success
  assert_output "$(printf '%s\n%s\n%s' \
    $'dockerfile_unchanged\t  Dockerfile unchanged: Dockerfile:4: ARG USER defaults to USER_NAME (an earlier upgrade\'s rewrite) or could not be read -- if sys never declares USER_NAME and creates the user from it, the image may run as root; '"${_port}"' (base#1322)' \
    $'dockerfile_unchanged\t  Dockerfile unchanged: Dockerfile:6: ARG USER has no default and compose passes no USER build arg -- unless a parent stage declares ARG USER (which this stage then inherits), the image does not get the user compose passes; '"${_port}"' (base#1322)' \
    $'dockerfile_migrations_reported\t  Dockerfile migrations: 1 of 1 matched (arg_user), 0 file(s) rewritten\tmatched=1\tavailable=1\tnames=arg_user\trewritten=0')"
}

# why: arg_user only reports, never rewrites: dockerfile golden == fixture, .files empty.
@test "s43 arg_user golden: dockerfile goldens equal their fixtures and files goldens are 0 bytes" {
  local _c
  for _c in parent_inherit case_from global_user_name sibling_stage inherited_stage decl_order quoting; do
    cmp -- "${CORPUS}/s43_arg_user_${_c}.Dockerfile" "${GOLDEN}/s43_arg_user_${_c}.dockerfile"
    [[ -f "${GOLDEN}/s43_arg_user_${_c}.files" ]]
    [[ ! -s "${GOLDEN}/s43_arg_user_${_c}.files" ]]
  done
}

# ── the partition check ─────────────────────────────────────────────────────

# why: each case has exactly one fixture and exactly three goldens.
@test "s43 arg_user golden: every case has one fixture and exactly its three goldens" {
  run _check_partition parent_inherit case_from global_user_name sibling_stage inherited_stage decl_order quoting
  assert_success
}
