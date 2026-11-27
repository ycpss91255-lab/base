#!/usr/bin/env bats
#
# Unit tests for script/ci/select_runner.sh -- the pure function that says
# whether the code of this event is trusted enough for a self-hosted
# runner, base#2265 (part of base#1586).
#
# The rule matches the existing self-hosted-guard: push (a tag push is a
# push too), workflow_dispatch, a same-repository pull_request and a
# merge_group proven same-repository are trusted; a fork, an empty head
# repository and every unlisted event are not. stdout is always one line,
# `trusted=true` or `trusted=false`, and the exit code is always 0.
#
# why: A wrong `true` hands a fork's code to a self-hosted runner, and a
# wrong `false` silently moves every run to the hosted pool. Each row of
# the issue's table is pinned so neither direction can drift (base#2265).

bats_require_minimum_version 1.5.0

setup() {
  load "${BATS_TEST_DIRNAME}/test_helper"
  SELECT="/source/script/ci/select_runner.sh"
  unset EVENT_NAME HEAD_REPO REPO MERGE_GROUP_SAME_REPO
}

# _run_row <event> <head_repo> <repo> <merge_group_same_repo>
_run_row() {
  EVENT_NAME="$1" HEAD_REPO="$2" REPO="$3" MERGE_GROUP_SAME_REPO="$4" \
    run --separate-stderr bash "${SELECT}"
}

@test "select_runner.sh: push is trusted (base#2265)" {
  _run_row push "" o/r ""
  assert_success
  assert_output "trusted=true"
}

@test "select_runner.sh: workflow_dispatch is trusted (base#2265)" {
  _run_row workflow_dispatch "" o/r ""
  assert_success
  assert_output "trusted=true"
}

@test "select_runner.sh: a same-repository pull_request is trusted (base#2265)" {
  _run_row pull_request o/r o/r ""
  assert_success
  assert_output "trusted=true"
}

@test "select_runner.sh: a fork pull_request is not trusted (base#2265)" {
  _run_row pull_request fork/r o/r ""
  assert_success
  assert_output "trusted=false"
}

@test "select_runner.sh: a pull_request with an empty head repository is not trusted (base#2265)" {
  _run_row pull_request "" o/r ""
  assert_success
  assert_output "trusted=false"
}

@test "select_runner.sh: a merge_group proven same-repository is trusted (base#2265)" {
  _run_row merge_group "" o/r true
  assert_success
  assert_output "trusted=true"
}

@test "select_runner.sh: a merge_group proven not same-repository is not trusted (base#2265)" {
  _run_row merge_group "" o/r false
  assert_success
  assert_output "trusted=false"
}

@test "select_runner.sh: a merge_group with no proof is not trusted (base#2265)" {
  _run_row merge_group "" o/r ""
  assert_success
  assert_output "trusted=false"
}

@test "select_runner.sh: schedule is not trusted (base#2265)" {
  _run_row schedule "" o/r ""
  assert_success
  assert_output "trusted=false"
}

@test "select_runner.sh: an unlisted event is not trusted (base#2265)" {
  _run_row issue_comment "" o/r ""
  assert_success
  assert_output "trusted=false"
}

@test "select_runner.sh: unset EVENT_NAME reports it on stderr and is not trusted (base#2265)" {
  REPO=o/r run --separate-stderr bash "${SELECT}"
  assert_success
  assert_output "trusted=false"
  [[ "${stderr}" == "::error::select_runner: EVENT_NAME is not set" ]]
}

@test "select_runner.sh: unset REPO reports it on stderr and is not trusted (base#2265)" {
  EVENT_NAME=push run --separate-stderr bash "${SELECT}"
  assert_success
  assert_output "trusted=false"
  [[ "${stderr}" == "::error::select_runner: REPO is not set" ]]
}
