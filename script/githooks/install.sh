#!/usr/bin/env bash
# install.sh - turn on the tracked git hooks in .githooks/ for this repo.
#
#   install.sh           set core.hooksPath=.githooks in this repo's config
#   install.sh --force   same, even if .git/hooks has active hooks
#   install.sh --check   exit 0 when the tracked hooks are active, 1 if not
#
# Writes only the local config, never --global. Refuses to replace another
# core.hooksPath, and refuses while .git/hooks holds an active hook,
# because core.hooksPath stops git from running those.
set -euo pipefail

readonly _HOOKS_PATH='.githooks'

_current_hooks_path() {
  git config --local --get core.hooksPath || true
}

# Prints each executable, non-sample hook under the repo's .git/hooks.
_active_legacy_hooks() {
  local _dir _f
  _dir="$(git rev-parse --git-common-dir)/hooks"
  [[ -d "${_dir}" ]] || return 0
  for _f in "${_dir}"/*; do
    [[ -f "${_f}" && -x "${_f}" ]] || continue
    [[ "${_f}" != *.sample ]] || continue
    printf '%s\n' "${_f##*/}"
  done
}

_check() {
  local _cur
  _cur="$(_current_hooks_path)"
  if [[ "${_cur}" == "${_HOOKS_PATH}" ]]; then
    echo "git hooks: active (core.hooksPath=${_HOOKS_PATH})"
    return 0
  fi
  echo "git hooks: not active (core.hooksPath='${_cur}'); run: just githooks install"
  return 1
}

_install() {
  local _force="${1}" _cur
  _cur="$(_current_hooks_path)"
  if [[ "${_cur}" == "${_HOOKS_PATH}" ]]; then
    echo "git hooks: already active (core.hooksPath=${_HOOKS_PATH})"
    return 0
  fi
  if [[ -n "${_cur}" ]]; then
    echo "git hooks: core.hooksPath is already '${_cur}'; not replacing it. Chain ${_HOOKS_PATH}/ from your hooks, or unset it and re-run." >&2
    return 1
  fi
  local -a _legacy=()
  mapfile -t _legacy < <(_active_legacy_hooks)
  if (( ${#_legacy[@]} > 0 )) && [[ "${_force}" != 1 ]]; then
    echo "git hooks: .git/hooks has active hooks that would stop running: ${_legacy[*]}. Re-run with --force to accept that." >&2
    return 1
  fi
  git config --local core.hooksPath "${_HOOKS_PATH}"
  echo "git hooks: active (core.hooksPath=${_HOOKS_PATH})"
}

main() {
  case "${1:-}" in
    --check) _check ;;
    --force) _install 1 ;;
    '') _install 0 ;;
    *) echo "usage: install.sh [--force | --check]" >&2; return 2 ;;
  esac
}

main "$@"
