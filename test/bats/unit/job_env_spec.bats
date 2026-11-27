#!/usr/bin/env bats
#
# Unit tests for script/ci/job_env.sh -- gives every CI job its own compose
# project name and TMPDIR, base#2274 (part of base#1586).
#
# The script is pure bash: inputs are GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT,
# JOB_KEY and RUNNER_TEMP, output is exactly two KEY=value lines on stdout.
# Expected values are the literals worked out in the issue's acceptance
# criteria, not recomputed here.
#
# why: Several cpu-runner jobs share one sibling docker daemon, so a fixed
# compose project name or /tmp path lets two jobs trample each other. The
# project name and TMPDIR must be unique per run/attempt/job, and TMPDIR
# must live under RUNNER_TEMP so sibling containers can see it, base#2274.

bats_require_minimum_version 1.5.0

setup() {
  load "${BATS_TEST_DIRNAME}/test_helper"

  JOB_ENV="/source/script/ci/job_env.sh"

  RT="${BATS_TEST_TMPDIR}/runner-temp"
  mkdir -p "${RT}"
}

# Run the script with a clean environment plus the given VAR=value words.
_run_env() {
  run --separate-stderr env -i PATH="${PATH}" "$@" bash "${JOB_ENV}"
}

# why: The one place the exact literals are pinned: the project name and TMPDIR format are what every workflow step will export, so any drift here changes names across all jobs, base#2274.
@test "job_env: worked example prints exactly the two documented lines" {
  _run_env GITHUB_RUN_ID=42 GITHUB_RUN_ATTEMPT=1 \
    JOB_KEY=Config-gen/Gates RUNNER_TEMP="${RT}"
  [ "${status}" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "COMPOSE_PROJECT_NAME=ci-42-1-config-gen-gates" ]
  [ "${lines[1]}" = "TMPDIR=${RT}/job-42-1-config-gen-gates" ]
}

# why: The script prints a path, but sibling containers need the directory to exist under RUNNER_TEMP; a printed-but-missing TMPDIR would fail only later inside the job, base#2274.
@test "job_env: creates the TMPDIR directory" {
  _run_env GITHUB_RUN_ID=42 GITHUB_RUN_ATTEMPT=1 \
    JOB_KEY=Config-gen/Gates RUNNER_TEMP="${RT}"
  [ "${status}" -eq 0 ]
  [ -d "${RT}/job-42-1-config-gen-gates" ]
}

# why: Distinct jobs of one run must not share a compose project or TMPDIR, which is the whole reason the script exists, base#2274.
@test "job_env: different JOB_KEY values give different output" {
  _run_env GITHUB_RUN_ID=42 GITHUB_RUN_ATTEMPT=1 \
    JOB_KEY=Lint RUNNER_TEMP="${RT}"
  [ "${status}" -eq 0 ]
  local first="${output}"
  [ "${lines[0]}" = "COMPOSE_PROJECT_NAME=ci-42-1-lint" ]

  _run_env GITHUB_RUN_ID=42 GITHUB_RUN_ATTEMPT=1 \
    JOB_KEY=Config-gen/Gates RUNNER_TEMP="${RT}"
  [ "${status}" -eq 0 ]
  [ "${output}" != "${first}" ]
}

# why: A job re-run in the same attempt hits an already-created directory; mkdir must not fail and the output must stay stable, base#2274.
@test "job_env: same input twice gives the same output and does not fail" {
  _run_env GITHUB_RUN_ID=42 GITHUB_RUN_ATTEMPT=1 \
    JOB_KEY=Config-gen/Gates RUNNER_TEMP="${RT}"
  [ "${status}" -eq 0 ]
  local first="${output}"

  _run_env GITHUB_RUN_ID=42 GITHUB_RUN_ATTEMPT=1 \
    JOB_KEY=Config-gen/Gates RUNNER_TEMP="${RT}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "${first}" ]
  [ -d "${RT}/job-42-1-config-gen-gates" ]
}

# why: A missing input must stop before anything is created or printed, so a half-formed name never reaches GITHUB_ENV, base#2274.
@test "job_env: missing GITHUB_RUN_ID reports it and creates nothing" {
  _run_env GITHUB_RUN_ATTEMPT=1 JOB_KEY=Lint RUNNER_TEMP="${RT}"
  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
  [ "${stderr}" = "::error::job_env: GITHUB_RUN_ID is not set" ]
  [ -z "$(ls -A "${RT}")" ]
}

# why: GitHub can hand over an empty value; it must be refused like an unset one, not folded into the name as an empty segment, base#2274.
@test "job_env: empty GITHUB_RUN_ATTEMPT counts as not set" {
  _run_env GITHUB_RUN_ID=42 GITHUB_RUN_ATTEMPT= JOB_KEY=Lint RUNNER_TEMP="${RT}"
  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
  [ "${stderr}" = "::error::job_env: GITHUB_RUN_ATTEMPT is not set" ]
  [ -z "$(ls -A "${RT}")" ]
}

# why: JOB_KEY is the only per-job part of the name; without it two jobs would collide, so it is refused, base#2274.
@test "job_env: missing JOB_KEY reports it" {
  _run_env GITHUB_RUN_ID=42 GITHUB_RUN_ATTEMPT=1 RUNNER_TEMP="${RT}"
  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
  [ "${stderr}" = "::error::job_env: JOB_KEY is not set" ]
  [ -z "$(ls -A "${RT}")" ]
}

# why: Without RUNNER_TEMP the TMPDIR would fall outside the path sibling containers can see, so the script refuses rather than guessing a location, base#2274.
@test "job_env: missing RUNNER_TEMP reports it" {
  _run_env GITHUB_RUN_ID=42 GITHUB_RUN_ATTEMPT=1 JOB_KEY=Lint
  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
  [ "${stderr}" = "::error::job_env: RUNNER_TEMP is not set" ]
}

# why: The error names one variable in a fixed order, so the message is deterministic and a test or a reader can predict which one is reported, base#2274.
@test "job_env: with several missing, only the first in check order is reported" {
  _run_env RUNNER_TEMP="${RT}"
  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
  [ "${stderr}" = "::error::job_env: GITHUB_RUN_ID is not set" ]
}
