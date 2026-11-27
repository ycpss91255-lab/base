#!/usr/bin/env bash
# pre-push.sh - body of .githooks/pre-push: the local first gate; CI runs
# the same checks and stays the real gate.
#
# Runs the workflow-run-name lint driver over this worktree's
# .github/workflows/. Pure bash, no Docker. Skip once with `git push
# --no-verify`.
set -euo pipefail

_self_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
_driver="${_self_dir}/../test/drivers/workflow_run_name.sh"

REPO_ROOT="$(git rev-parse --show-toplevel)"

# Stand-in for _lib.sh's _die: message to stderr, non-zero status.
_die() {
  shift
  printf 'pre-push: %s\n' "$*" >&2
  return 1
}

# shellcheck source=script/test/drivers/workflow_run_name.sh
source "${_driver}"

if ! _run_workflow_run_name; then
  printf 'pre-push: blocked. Fix the workflows above, or skip once with git push --no-verify (CI still checks).\n' >&2
  exit 1
fi
