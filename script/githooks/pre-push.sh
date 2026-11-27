#!/usr/bin/env bash
# pre-push.sh - body of .githooks/pre-push: the local first gate; CI runs
# the same checks and stays the real gate.
#
# Reads the ref lines git writes on stdin. For each pushed tag, checks its
# name with script/release/tag_format.sh. For each pushed commit, runs the
# workflow-run-name lint driver over its .github/workflows/; the working
# tree is not what reaches the remote, so it is not read. Pure bash, no
# Docker. Skip once with `git push --no-verify`.
set -euo pipefail

_self_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
_driver="${_self_dir}/../test/drivers/workflow_run_name.sh"
_tag_format="${_self_dir}/../release/tag_format.sh"

# Stand-in for _lib.sh's _die: message to stderr, non-zero status.
_die() {
  shift
  printf 'pre-push: %s\n' "$*" >&2
  return 1
}

# shellcheck source=script/test/drivers/workflow_run_name.sh
source "${_driver}"

_tmp="$(mktemp -d)"
trap 'rm -rf "${_tmp}"' EXIT

_rc=0
_seen=" "
# Each line: <local ref> <local sha> <remote ref> <remote sha>; a last
# line without a newline is still read.
while read -r _local_ref _local_sha _remote_ref _ || [[ -n "${_local_ref:-}" ]]; do
  [[ -n "${_local_sha:-}" ]] || continue
  # An all-zero local sha is a deletion: no commit is pushed.
  [[ "${_local_sha}" =~ ^0+$ ]] && continue
  # Before the seen-commit skip: a tag often shares its branch's commit.
  if [[ "${_remote_ref:-}" == refs/tags/* ]]; then
    bash "${_tag_format}" "${_remote_ref}" || _rc=1
  fi
  [[ "${_seen}" == *" ${_local_sha} "* ]] && continue
  _seen+="${_local_sha} "

  REPO_ROOT="${_tmp}/${_local_sha}"
  mkdir -p "${REPO_ROOT}"
  # A commit without the directory is left empty, which the driver refuses.
  if git cat-file -e "${_local_sha}:${_WORKFLOW_RUN_NAME_DIR_REL}" 2>/dev/null; then
    git archive "${_local_sha}" -- "${_WORKFLOW_RUN_NAME_DIR_REL}" | tar -x -C "${REPO_ROOT}"
  fi
  printf 'pre-push: checking %s (%s)\n' "${_local_ref}" "${_local_sha:0:12}"
  _run_workflow_run_name || _rc=1
done

if (( _rc != 0 )); then
  printf 'pre-push: blocked. Fix the tag name or the workflows above in the pushed commit, or skip once with git push --no-verify (CI still checks).\n' >&2
  exit 1
fi
