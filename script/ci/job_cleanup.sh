#!/usr/bin/env bash
# job_cleanup.sh - Remove this job's compose project and its TMPDIR.
#
# Usage: COMPOSE_PROJECT_NAME=<project> TMPDIR=<.../job-...> job_cleanup.sh
#
# Runs when a CI job ends. Siblings share one host docker daemon, so the
# removal is scoped to this job's compose project only; there is no global
# prune, base#2275.
set -euo pipefail

project="${COMPOSE_PROJECT_NAME:-}"
tmp="${TMPDIR:-}"

# An empty project name would make the compose down unscoped, base#2275.
if [[ -z "${project}" ]]; then
  printf '::error::job_cleanup: COMPOSE_PROJECT_NAME is not set\n' >&2
  exit 1
fi

# Only a per-job TMPDIR is removed; a shared one (e.g. /tmp) never is.
if [[ "${tmp}" != */job-* ]]; then
  printf '::error::job_cleanup: refusing to remove %s\n' "${tmp}" >&2
  exit 1
fi

# Cleanup runs after a failed job and must not turn the step red.
if ! docker compose -p "${project}" down --volumes --remove-orphans; then
  printf '::warning::job_cleanup: docker compose down failed\n' >&2
fi

rm -rf -- "${tmp}"
