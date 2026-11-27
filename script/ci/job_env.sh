#!/usr/bin/env bash
# job_env.sh - Print a per-job COMPOSE_PROJECT_NAME and TMPDIR.
#
# Usage: GITHUB_RUN_ID=.. GITHUB_RUN_ATTEMPT=.. JOB_KEY=.. RUNNER_TEMP=.. \
#          job_env.sh >> "$GITHUB_ENV"
#
# Output is exactly two KEY=value lines. The TMPDIR is created under
# RUNNER_TEMP so sibling containers on the shared docker daemon can see it.
# Jobs on one runner host share that daemon, so a fixed compose project name
# or /tmp path would let two jobs trample each other, base#2274.
set -euo pipefail

for var in GITHUB_RUN_ID GITHUB_RUN_ATTEMPT JOB_KEY RUNNER_TEMP; do
  if [[ -z "${!var:-}" ]]; then
    printf '::error::job_env: %s is not set\n' "${var}" >&2
    exit 1
  fi
done

# Lowercase, every run of non [a-z0-9] becomes one '-', no edge dashes.
slug="${JOB_KEY,,}"
slug="${slug//[^a-z0-9]/-}"
while [[ "${slug}" == *--* ]]; do
  slug="${slug//--/-}"
done
slug="${slug#-}"
slug="${slug%-}"

id="${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}-${slug}"
tmp="${RUNNER_TEMP}/job-${id}"

mkdir -p "${tmp}"

printf 'COMPOSE_PROJECT_NAME=ci-%s\n' "${id}"
printf 'TMPDIR=%s\n' "${tmp}"
