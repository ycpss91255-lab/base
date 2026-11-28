#!/usr/bin/env bash
# fleet_jobs.sh - Merge the jobs of the queued and in-progress runs.
#
# Usage: REPO=<owner/repo> GH_TOKEN=<token> fleet_jobs.sh | fleet_stuck.sh
#
# Prints one JSON array of every job of every queued and in_progress run, the
# input fleet_stuck.sh reads, base#2317 (part of base#1586). A `gh api` that
# fails for one run drops only that run's jobs and prints a `::warning::`
# naming the run id on stderr. Total failure prints `[]`. The exit status is
# always 0, so a classify step that calls it never fails on an API error.
set -uo pipefail

collect() {
  local status run_id ids
  for status in queued in_progress; do
    if ! ids="$(gh api "repos/${REPO}/actions/runs?status=${status}&per_page=20" \
      --jq '.workflow_runs[].id' 2>/dev/null)"; then
      printf '::warning::fleet_jobs: cannot list %s runs\n' "${status}" >&2
      continue
    fi
    for run_id in ${ids}; do
      if ! gh api --paginate "repos/${REPO}/actions/runs/${run_id}/jobs" \
        --jq '.jobs[]' 2>/dev/null; then
        printf '::warning::fleet_jobs: cannot read jobs of run %s\n' "${run_id}" >&2
      fi
    done
  done
}

collect | jq -s . 2>/dev/null || printf '[]\n'
exit 0
