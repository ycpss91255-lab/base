#!/usr/bin/env bats
#
# Unit tests for script/ci/fleet_jobs.sh -- merges the jobs of the queued and
# in-progress runs into one JSON array for fleet_stuck.sh, base#2317 (part of
# base#1586).
#
# Contract: REPO and GH_TOKEN in the environment, `gh` on PATH. stdout is one
# JSON array of every job of every listed run. A `gh api` that fails for one
# run drops only that run's jobs and prints `::warning::` naming the run id on
# stderr. Total failure prints `[]`. The exit status is always 0.
#
# The fake `gh` below answers from fixture files and applies the caller's
# --jq expression with the real jq, so the spec does not depend on which jq
# filter the script chooses.

bats_require_minimum_version 1.5.0

setup() {
  load "${BATS_TEST_DIRNAME}/test_helper"
  JOBS="/source/script/ci/fleet_jobs.sh"
  FAKE="${BATS_TEST_TMPDIR}/fake"
  mkdir -p "${FAKE}/bin"
  cat >"${FAKE}/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Fake gh: `gh api [--paginate] <endpoint> [--jq <expr>]`.
fix="${FAKE_GH_DIR}"
endpoint="" jq_expr=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    api|--paginate) ;;
    --jq) shift; jq_expr="$1" ;;
    *) endpoint="$1" ;;
  esac
  shift
done
case "${endpoint}" in
  */actions/runs\?status=*)
    file="${fix}/runs_${endpoint##*status=}.json" ;;
  */actions/runs/*/jobs)
    id="${endpoint%/jobs}"; id="${id##*/}"
    file="${fix}/jobs_${id}.json" ;;
  *) echo "fake gh: unexpected ${endpoint}" >&2; exit 2 ;;
esac
if [[ -e "${fix}/fail_all" || ! -e "${file}" ]]; then
  echo "gh: HTTP 403" >&2
  exit 1
fi
if [[ -n "${jq_expr}" ]]; then
  jq -c "${jq_expr}" "${file}"
else
  cat "${file}"
fi
EOF
  chmod +x "${FAKE}/bin/gh"
  export FAKE_GH_DIR="${FAKE}"
  export PATH="${FAKE}/bin:${PATH}"
  export REPO="o/r" GH_TOKEN="x"
}

# _runs <status> <id>...
_runs() {
  local status="$1" ids="" id
  shift
  for id in "$@"; do ids+="{\"id\":${id}},"; done
  printf '{"workflow_runs":[%s]}' "${ids%,}" >"${FAKE}/runs_${status}.json"
}

# _jobs <run id> <job id>...
_jobs() {
  local run="$1" jobs="" id
  shift
  for id in "$@"; do jobs+="{\"id\":${id},\"status\":\"queued\"},"; done
  printf '{"jobs":[%s]}' "${jobs%,}" >"${FAKE}/jobs_${run}.json"
}

# why: fleet_stuck.sh reads one array, but the API lists jobs per run. Runs from
# both the queued and the in-progress listing must all land in that array, or a
# stuck job in the second listing is never seen (base#2317).
@test "fleet_jobs.sh: merges the jobs of several runs into one array (base#2317)" {
  _runs queued 11 12
  _runs in_progress 21
  _jobs 11 111 112
  _jobs 12 121
  _jobs 21 211
  run --separate-stderr bash "${JOBS}"
  assert_success
  run jq -c '[.[].id] | sort' <<<"${output}"
  assert_success
  assert_output '[111,112,121,211]'
}

# why: One run can answer 403/404 (another workflow, a deleted run). Dropping
# every run's jobs for that would hide a stuck fleet, so only the failing run is
# skipped and its id is named in a warning (base#2317).
@test "fleet_jobs.sh: a failing run keeps the other runs' jobs and warns with its id (base#2317)" {
  _runs queued 11 12
  _runs in_progress
  _jobs 11 111
  # No jobs_12.json: the fake gh fails for run 12.
  run --separate-stderr bash "${JOBS}"
  assert_success
  run jq -c '[.[].id]' <<<"${output}"
  assert_output '[111]'
  run --separate-stderr bash "${JOBS}"
  [[ "${stderr}" == *"::warning::"*12* ]]
}

# why: When the API is down or the token lacks actions: read, the step must
# still produce valid input for fleet_stuck.sh and must not fail classify:
# `[]`, exit 0 (base#2317).
@test "fleet_jobs.sh: total API failure prints [] and exits 0 (base#2317)" {
  touch "${FAKE}/fail_all"
  run --separate-stderr bash "${JOBS}"
  assert_success
  assert_output '[]'
  [[ "${stderr}" == *"::warning::"* ]]
}
