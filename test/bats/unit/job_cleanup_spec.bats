#!/usr/bin/env bats
#
# Unit tests for script/ci/job_cleanup.sh -- removes only this job's compose
# project and its TMPDIR when a job ends (base#2275, part of base#1586).
#
# The seam is the script's CLI: env COMPOSE_PROJECT_NAME / TMPDIR in, the
# exact docker argv, the TMPDIR state, stderr and the exit code out. docker
# is a stub on PATH that records each call's arguments, so no daemon is
# needed. Expected argv and messages are the literals from the issue table.

setup() {
  SCRIPT=/source/script/ci/job_cleanup.sh
  MOCK_DIR="${BATS_TEST_TMPDIR}/mock"
  CALLS="${BATS_TEST_TMPDIR}/docker.calls"
  ERR="${BATS_TEST_TMPDIR}/stderr"
  mkdir -p "${MOCK_DIR}"
  : > "${CALLS}"
}

# _stub_docker <exit-code> -- a docker that records one line per call
# (its arguments joined by single spaces) and exits <exit-code>.
_stub_docker() {
  cat > "${MOCK_DIR}/docker" <<STUB
#!/bin/sh
echo "\$*" >> "${CALLS}"
exit $1
STUB
  chmod +x "${MOCK_DIR}/docker"
}

# _run_cleanup <project> <tmpdir> -- run the script with the stub on PATH,
# stderr captured to ${ERR}.
_run_cleanup() {
  run bash -c 'PATH="$1:$PATH" COMPOSE_PROJECT_NAME="$2" TMPDIR="$3" bash "$4" 2>"$5"' \
    _ "${MOCK_DIR}" "$1" "$2" "${SCRIPT}" "${ERR}"
}

# why: base#2275 -- the happy path removes exactly one compose project, then
# the job TMPDIR.
@test "job_cleanup: runs one scoped compose down, then removes TMPDIR, exit 0" {
  _stub_docker 0
  local tmp="${BATS_TEST_TMPDIR}/job-123-1"
  mkdir -p "${tmp}"
  : > "${tmp}/scratch"

  _run_cleanup base-123-1 "${tmp}"

  [ "${status}" -eq 0 ]
  [ "$(wc -l < "${CALLS}")" -eq 1 ]
  [ "$(cat "${CALLS}")" = "compose -p base-123-1 down --volumes --remove-orphans" ]
  [ ! -e "${tmp}" ]
}

# why: base#2275 -- a job that created nothing must still clean up quietly.
@test "job_cleanup: nothing to remove (TMPDIR absent, stub exits 0) is not an error" {
  _stub_docker 0
  local tmp="${BATS_TEST_TMPDIR}/job-123-1"

  _run_cleanup base-123-1 "${tmp}"

  [ "${status}" -eq 0 ]
  [ ! -s "${ERR}" ]
}

# why: base#2275 -- cleanup runs after a failed job and must not turn the
# step red; TMPDIR is removed regardless of the docker result.
@test "job_cleanup: docker failure still removes TMPDIR, warns once, exits 0" {
  _stub_docker 1
  local tmp="${BATS_TEST_TMPDIR}/job-123-1"
  mkdir -p "${tmp}"

  _run_cleanup base-123-1 "${tmp}"

  [ "${status}" -eq 0 ]
  [ ! -e "${tmp}" ]
  [ "$(grep -c '^::warning::job_cleanup: docker compose down failed$' "${ERR}")" -eq 1 ]
}

# why: base#2275 -- without a project name the compose down would be
# unscoped; refuse before touching docker or TMPDIR.
@test "job_cleanup: empty COMPOSE_PROJECT_NAME errors, no docker call, TMPDIR kept" {
  _stub_docker 0
  local tmp="${BATS_TEST_TMPDIR}/job-123-1"
  mkdir -p "${tmp}"

  _run_cleanup "" "${tmp}"

  [ "${status}" -eq 1 ]
  [ ! -s "${CALLS}" ]
  [ -d "${tmp}" ]
  grep -qxF '::error::job_cleanup: COMPOSE_PROJECT_NAME is not set' "${ERR}"
}

@test "job_cleanup: unset COMPOSE_PROJECT_NAME errors, no docker call, TMPDIR kept" {
  _stub_docker 0
  local tmp="${BATS_TEST_TMPDIR}/job-123-1"
  mkdir -p "${tmp}"

  run bash -c 'unset COMPOSE_PROJECT_NAME; PATH="$1:$PATH" TMPDIR="$2" bash "$3" 2>"$4"' \
    _ "${MOCK_DIR}" "${tmp}" "${SCRIPT}" "${ERR}"

  [ "${status}" -eq 1 ]
  [ ! -s "${CALLS}" ]
  [ -d "${tmp}" ]
  grep -qxF '::error::job_cleanup: COMPOSE_PROJECT_NAME is not set' "${ERR}"
}

# why: base#2275 -- a TMPDIR without the /job- prefix (e.g. the shared
# /tmp) must never be deleted.
@test "job_cleanup: TMPDIR without /job- is refused, nothing removed" {
  _stub_docker 0
  local tmp="${BATS_TEST_TMPDIR}/shared"
  mkdir -p "${tmp}"
  : > "${tmp}/keep"

  _run_cleanup base-123-1 "${tmp}"

  [ "${status}" -eq 1 ]
  [ -e "${tmp}/keep" ]
  grep -qxF "::error::job_cleanup: refusing to remove ${tmp}" "${ERR}"
}

# why: base#2275 -- scope limit: only the one project, never a global prune
# or an unscoped removal.
@test "job_cleanup: script text has no system prune, docker rm or network rm" {
  [ -f "${SCRIPT}" ]
  run grep -nE 'docker[[:space:]]+(system[[:space:]]+prune|rm|network[[:space:]]+rm)' "${SCRIPT}"
  [ "${status}" -ne 0 ]
}
