#!/usr/bin/env bash
# job_env.sh - Print a per-job COMPOSE_PROJECT_NAME, TMPDIR, TEST_TOOLS_IMAGE and CI_RUN_KEY.
#
# Usage: GITHUB_RUN_ID=.. GITHUB_RUN_ATTEMPT=.. JOB_KEY=.. RUNNER_TEMP=.. \
#          job_env.sh >> "$GITHUB_ENV"
#
# Output is exactly four KEY=value lines. The TMPDIR is created under
# RUNNER_TEMP so sibling containers on the shared docker daemon can see it.
# Jobs on one runner host share that daemon, so a fixed compose project name
# or /tmp path would let two jobs trample each other, base#2274. The image
# tag shares the id so jobs do not overwrite one test-tools tag, base#2321.
# CI_RUN_KEY is the same id, so a reclaim step can target only this job, base#2328.
set -euo pipefail

for var in GITHUB_RUN_ID GITHUB_RUN_ATTEMPT JOB_KEY RUNNER_TEMP; do
  if [[ -z "${!var:-}" ]]; then
    printf '::error::job_env: %s is not set\n' "${var}" >&2
    exit 1
  fi
done

# Lowercase, every non [a-z0-9] character becomes one '-'; no collapsing or
# trimming, so distinct JOB_KEYs stay distinct (a-b vs a--b), base#2274.
slug="${JOB_KEY,,}"
slug="${slug//[^a-z0-9]/-}"

id="${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}-${slug}"
tmp="${RUNNER_TEMP}/job-${id}"

mkdir -p "${tmp}"

printf 'COMPOSE_PROJECT_NAME=ci-%s\n' "${id}"
printf 'TMPDIR=%s\n' "${tmp}"
printf 'TEST_TOOLS_IMAGE=test-tools:ci-%s\n' "${id}"
printf 'CI_RUN_KEY=%s\n' "${id}"
