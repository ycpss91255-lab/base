#!/usr/bin/env bats
#
# Unit tests for script/ci/select_runner.sh -- the pure function that says
# whether the code of this event is trusted enough for a self-hosted
# runner, base#2265 (part of base#1586).
#
# The rule matches the existing self-hosted-guard: push (a tag push is a
# push too), workflow_dispatch, a same-repository pull_request and a
# merge_group proven same-repository are trusted; a fork, an empty head
# repository and every unlisted event are not. The first stdout line is
# `trusted=true` or `trusted=false`, and the exit code is always 0.
#
# why: A wrong `true` hands a fork's code to a self-hosted runner, and a
# wrong `false` silently moves every run to the hosted pool. Each row of
# the issue's table is pinned so neither direction can drift (base#2265).

bats_require_minimum_version 1.5.0

setup() {
  load "${BATS_TEST_DIRNAME}/test_helper"
  SELECT="/source/script/ci/select_runner.sh"
  unset EVENT_NAME HEAD_REPO REPO MERGE_GROUP_SAME_REPO CI_SELF_HOSTED
}

# _run_row <event> <head_repo> <repo> <merge_group_same_repo>
_run_row() {
  EVENT_NAME="$1" HEAD_REPO="$2" REPO="$3" MERGE_GROUP_SAME_REPO="$4" \
    run --separate-stderr bash "${SELECT}"
}

# why: A tag push is a push too; answering false would move every release run to the hosted pool (base#2265).
@test "select_runner.sh: push is trusted (base#2265)" {
  _run_row push "" o/r ""
  assert_success
  assert_equal "${lines[0]}" "trusted=true"
}

# why: Only someone with write access can dispatch, so the run is the owner's own code (base#2265).
@test "select_runner.sh: workflow_dispatch is trusted (base#2265)" {
  _run_row workflow_dispatch "" o/r ""
  assert_success
  assert_equal "${lines[0]}" "trusted=true"
}

# why: The head repository equals this one, so the code was pushed by someone with write access (base#2265).
@test "select_runner.sh: a same-repository pull_request is trusted (base#2265)" {
  _run_row pull_request o/r o/r ""
  assert_success
  assert_equal "${lines[0]}" "trusted=true"
}

# why: A fork's code on a self-hosted runner is the exact hole this script closes (base#2265).
@test "select_runner.sh: a fork pull_request is not trusted (base#2265)" {
  _run_row pull_request fork/r o/r ""
  assert_success
  assert_equal "${lines[0]}" "trusted=false"
}

# why: An empty head repository proves nothing about who wrote the code, so it fails closed (base#2265).
@test "select_runner.sh: a pull_request with an empty head repository is not trusted (base#2265)" {
  _run_row pull_request "" o/r ""
  assert_success
  assert_equal "${lines[0]}" "trusted=false"
}

# why: The only case that opens a self-hosted runner on a queue run (base#2265).
@test "select_runner.sh: a merge_group proven same-repository is trusted (base#2265)" {
  _run_row merge_group "" o/r true
  assert_success
  assert_equal "${lines[0]}" "trusted=true"
}

# why: A group holding a fork's pull request must stay on the hosted pool (base#2265).
@test "select_runner.sh: a merge_group proven not same-repository is not trusted (base#2265)" {
  _run_row merge_group "" o/r false
  assert_success
  assert_equal "${lines[0]}" "trusted=false"
}

# why: A merge_group payload names no head repository, so no proof means false (base#2265).
@test "select_runner.sh: a merge_group with no proof is not trusted (base#2265)" {
  _run_row merge_group "" o/r ""
  assert_success
  assert_equal "${lines[0]}" "trusted=false"
}

# why: A schedule is not in the listed events; the default answer is false (base#2265).
@test "select_runner.sh: schedule is not trusted (base#2265)" {
  _run_row schedule "" o/r ""
  assert_success
  assert_equal "${lines[0]}" "trusted=false"
}

# why: An event nobody listed (issue_comment) can carry attacker text, so the default is false (base#2265).
@test "select_runner.sh: an unlisted event is not trusted (base#2265)" {
  _run_row issue_comment "" o/r ""
  assert_success
  assert_equal "${lines[0]}" "trusted=false"
}

# why: A missing input must be named on stderr and answered false, never read as trusted (base#2265).
@test "select_runner.sh: unset EVENT_NAME reports it on stderr and is not trusted (base#2265)" {
  REPO=o/r run --separate-stderr bash "${SELECT}"
  assert_success
  assert_equal "${lines[0]}" "trusted=false"
  [[ "${stderr}" == "::error::select_runner: EVENT_NAME is not set" ]]
}

# why: Without REPO a same-repository comparison is meaningless, so it names the variable and answers false (base#2265).
@test "select_runner.sh: unset REPO reports it on stderr and is not trusted (base#2265)" {
  EVENT_NAME=push run --separate-stderr bash "${SELECT}"
  assert_success
  assert_equal "${lines[0]}" "trusted=false"
  [[ "${stderr}" == "::error::select_runner: REPO is not set" ]]
}

# --- runs_on: CI_SELF_HOSTED master switch, base#2266 (part of base#1586) ---
#
# stdout is exactly two lines: `trusted=...` then `runs_on=<compact JSON
# array>`. Only a trusted event with CI_SELF_HOSTED=cpu gets the CPU fleet
# label set; every other row falls back to hosted ubuntu-latest.

# _run_switch <event> <head_repo> <repo> <ci_self_hosted>
_run_switch() {
  EVENT_NAME="$1" HEAD_REPO="$2" REPO="$3" CI_SELF_HOSTED="$4" \
    run --separate-stderr bash "${SELECT}"
}

# why: The switch on with a trusted event is the only way to reach the CPU fleet (base#2266).
@test "select_runner.sh: trusted + CI_SELF_HOSTED=cpu selects the cpu fleet (base#2266)" {
  _run_switch push "" o/r cpu
  assert_success
  assert_equal "${#lines[@]}" 2
  assert_equal "${lines[0]}" "trusted=true"
  assert_equal "${lines[1]}" 'runs_on=["self-hosted","linux","x64","cpu"]'
}

# why: An unset switch is the rollback path, so a trusted event stays on hosted (base#2266).
@test "select_runner.sh: trusted + CI_SELF_HOSTED unset selects ubuntu-latest (base#2266)" {
  _run_switch push "" o/r ""
  assert_success
  assert_equal "${#lines[@]}" 2
  assert_equal "${lines[0]}" "trusted=true"
  assert_equal "${lines[1]}" 'runs_on=["ubuntu-latest"]'
}

# why: Only the value cpu opens the fleet; gpu has no fleet here, so it falls back (base#2266).
@test "select_runner.sh: trusted + CI_SELF_HOSTED=gpu selects ubuntu-latest (base#2266)" {
  _run_switch push "" o/r gpu
  assert_success
  assert_equal "${#lines[@]}" 2
  assert_equal "${lines[0]}" "trusted=true"
  assert_equal "${lines[1]}" 'runs_on=["ubuntu-latest"]'
}

# why: A fork must never get a self-hosted runner, even with the switch on (base#2266).
@test "select_runner.sh: a fork pull_request with CI_SELF_HOSTED=cpu selects ubuntu-latest (base#2266)" {
  _run_switch pull_request fork/r o/r cpu
  assert_success
  assert_equal "${#lines[@]}" 2
  assert_equal "${lines[0]}" "trusted=false"
  assert_equal "${lines[1]}" 'runs_on=["ubuntu-latest"]'
}

# why: An unlisted event is untrusted, so the switch cannot lift it onto self-hosted (base#2266).
@test "select_runner.sh: schedule with CI_SELF_HOSTED=cpu selects ubuntu-latest (base#2266)" {
  _run_switch schedule "" o/r cpu
  assert_success
  assert_equal "${#lines[@]}" 2
  assert_equal "${lines[0]}" "trusted=false"
  assert_equal "${lines[1]}" 'runs_on=["ubuntu-latest"]'
}

# why: A missing EVENT_NAME fails closed to hosted while the error line stays as before (base#2266).
@test "select_runner.sh: unset EVENT_NAME with CI_SELF_HOSTED=cpu selects ubuntu-latest (base#2266)" {
  REPO=o/r CI_SELF_HOSTED=cpu run --separate-stderr bash "${SELECT}"
  assert_success
  assert_equal "${#lines[@]}" 2
  assert_equal "${lines[0]}" "trusted=false"
  assert_equal "${lines[1]}" 'runs_on=["ubuntu-latest"]'
  [[ "${stderr}" == "::error::select_runner: EVENT_NAME is not set" ]]
}

# why: A missing REPO fails closed to hosted while the error line stays as before (base#2266).
@test "select_runner.sh: unset REPO with CI_SELF_HOSTED=cpu selects ubuntu-latest (base#2266)" {
  EVENT_NAME=push CI_SELF_HOSTED=cpu run --separate-stderr bash "${SELECT}"
  assert_success
  assert_equal "${#lines[@]}" 2
  assert_equal "${lines[0]}" "trusted=false"
  assert_equal "${lines[1]}" 'runs_on=["ubuntu-latest"]'
  [[ "${stderr}" == "::error::select_runner: REPO is not set" ]]
}
