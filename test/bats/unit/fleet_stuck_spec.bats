#!/usr/bin/env bats
#
# Unit tests for script/ci/fleet_stuck.sh -- says whether a self-hosted job
# has sat queued too long, base#2288 (part of base#1586).
#
# stdin is the merged `jobs` array of GET /repos/{repo}/actions/runs/{id}/jobs,
# NOW is epoch seconds, STUCK_MINUTES defaults to 15. A job makes the fleet
# stuck when it is queued, carries the `self-hosted` label and has waited at
# least STUCK_MINUTES. Output is `stuck=true|false` on stdout, exit 0.
#
# why: A wrong `true` moves a healthy run to the hosted pool, and a wrong
# `false` leaves a run waiting on a dead fleet. Each row of the issue's table
# is pinned so the 14/15 minute boundary cannot drift (base#2288).
#
# Time anchor: created_at 2026-11-28T10:00:00Z is epoch 1795860000 (taken from
# `date -u -d`), so +14 min is 1795860840 and +15 min is 1795860900.

bats_require_minimum_version 1.5.0

setup() {
  load "${BATS_TEST_DIRNAME}/test_helper"
  STUCK="/source/script/ci/fleet_stuck.sh"
  unset NOW STUCK_MINUTES
}

# _run_stuck <now> <json> [stuck_minutes]
_run_stuck() {
  local now="$1" json="$2"
  if [[ $# -ge 3 ]]; then
    NOW="${now}" STUCK_MINUTES="$3" run --separate-stderr bash "${STUCK}" <<<"${json}"
  else
    NOW="${now}" run --separate-stderr bash "${STUCK}" <<<"${json}"
  fi
}

# why: An empty jobs array has nothing waiting, so the fleet is not stuck (base#2288).
@test "fleet_stuck.sh: no jobs is not stuck (base#2288)" {
  _run_stuck 1795860900 '[]'
  assert_success
  assert_equal "${output}" "stuck=false"
  assert_equal "${stderr}" ""
}

# why: A queued hosted job says nothing about the self-hosted fleet (base#2288).
@test "fleet_stuck.sh: only a hosted job queued is not stuck (base#2288)" {
  _run_stuck 1795860900 '[{"status":"queued","labels":["ubuntu-latest"],"created_at":"2026-11-28T10:00:00Z"}]'
  assert_success
  assert_equal "${output}" "stuck=false"
  assert_equal "${stderr}" ""
}

# why: 14 minutes is under the 15 minute default, so no fallback yet (base#2288).
@test "fleet_stuck.sh: self-hosted queued 14 minutes is not stuck (base#2288)" {
  _run_stuck 1795860840 '[{"status":"queued","labels":["self-hosted","linux","x64","cpu"],"created_at":"2026-11-28T10:00:00Z"}]'
  assert_success
  assert_equal "${output}" "stuck=false"
  assert_equal "${stderr}" ""
}

# why: The threshold is inclusive, so exactly 15 minutes is stuck (base#2288).
@test "fleet_stuck.sh: self-hosted queued 15 minutes is stuck (base#2288)" {
  _run_stuck 1795860900 '[{"status":"queued","labels":["self-hosted","linux","x64","cpu"],"created_at":"2026-11-28T10:00:00Z"}]'
  assert_success
  assert_equal "${output}" "stuck=true"
  assert_equal "${stderr}" ""
}

# why: An in_progress job was picked up by a runner, so the fleet is alive (base#2288).
@test "fleet_stuck.sh: self-hosted in_progress is not stuck (base#2288)" {
  _run_stuck 1795860900 '[{"status":"in_progress","labels":["self-hosted","linux","x64","cpu"],"created_at":"2026-11-28T10:00:00Z"}]'
  assert_success
  assert_equal "${output}" "stuck=false"
  assert_equal "${stderr}" ""
}

# why: STUCK_MINUTES overrides the default, so 5 minutes of waiting is stuck at 5 (base#2288).
@test "fleet_stuck.sh: STUCK_MINUTES=5 makes a 5 minute wait stuck (base#2288)" {
  _run_stuck 1795860300 '[{"status":"queued","labels":["self-hosted","linux","x64","cpu"],"created_at":"2026-11-28T10:00:00Z"}]' 5
  assert_success
  assert_equal "${output}" "stuck=true"
  assert_equal "${stderr}" ""
}

# why: Unreadable input must never strand a run, so it answers false with a warning (base#2288).
@test "fleet_stuck.sh: unparseable input is not stuck and warns (base#2288)" {
  _run_stuck 1795860900 'this is not json'
  assert_success
  assert_equal "${output}" "stuck=false"
  assert_equal "${stderr}" "::warning::fleet_stuck: unreadable jobs input"
}

# why: Empty stdin is also unreadable and gets the same warning (base#2288).
@test "fleet_stuck.sh: empty input is not stuck and warns (base#2288)" {
  _run_stuck 1795860900 ''
  assert_success
  assert_equal "${output}" "stuck=false"
  assert_equal "${stderr}" "::warning::fleet_stuck: unreadable jobs input"
}
