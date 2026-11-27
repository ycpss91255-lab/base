#!/usr/bin/env bash
# fleet_stuck.sh - Say whether a self-hosted job has sat queued too long.
#
# Usage: NOW=<epoch seconds> [STUCK_MINUTES=15] fleet_stuck.sh < jobs.json
#
# stdin is the merged `jobs` array of GET /repos/{repo}/actions/runs/{id}/jobs.
# Prints `stuck=true|false` on stdout and always exits 0. The fleet is stuck
# when a job is `queued`, carries the `self-hosted` label and has waited at
# least STUCK_MINUTES (inclusive), base#2288 (part of base#1586).
#
# Input that is not a JSON array (empty, garbage) proves nothing: it prints a
# `::warning::` line on stderr and answers false, so a run is never moved on
# unreadable data.
set -euo pipefail

minutes="${STUCK_MINUTES:-15}"
now="${NOW:-$(date +%s)}"

jobs_json="$(cat)"

if ! stuck="$(jq -r --argjson now "${now}" --argjson mins "${minutes}" '
  if type != "array" then error("not an array") else
    any(.[]; .status == "queued"
      and ((.labels // []) | index("self-hosted") != null)
      and ($now - (.created_at | fromdateiso8601)) >= ($mins * 60))
  end' <<<"${jobs_json}" 2>/dev/null)" || [[ -z "${stuck}" ]]; then
  printf '::warning::fleet_stuck: unreadable jobs input\n' >&2
  printf 'stuck=false\n'
  exit 0
fi

printf 'stuck=%s\n' "${stuck}"
