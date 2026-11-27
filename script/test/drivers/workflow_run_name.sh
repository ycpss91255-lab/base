#!/usr/bin/env bash
# drivers/workflow_run_name.sh - "every workflow sets a dynamic run-name"
# per-tool driver for the self-test dispatcher.
#
# Sourced library (no main): test.sh sources this after _lib.sh, so _die
# and the _log_* helpers exist. Provides _run_workflow_run_name.
#
# Contract: pure bash + awk over ${REPO_ROOT}, so it runs host-direct and
# inside the ci (test-tools) container alike.
#
# Rule: each .github/workflows/*.yaml and *.yml has a top-level `run-name:`
# whose value holds a `${{ ... }}` expression.
#   - Without one, the Actions list titles every run with the workflow name
#     or the PR title, so runs of one PR or of the merge queue look alike.
#   - Static text is refused for the same reason.
#   - The expression must read github.event.merge_group.head_ref: a merge
#     queue run is traced to its PR only through that ref.
#   - Only a column-0 key counts; a commented or indented one does not.
#   - Zero workflow files is a failure, not a pass.

readonly _WORKFLOW_RUN_NAME_DIR_REL='.github/workflows'
# shellcheck disable=SC2016 # literal expression delimiters, not expansions.
readonly _WORKFLOW_RUN_NAME_OPEN='${{' _WORKFLOW_RUN_NAME_CLOSE='}}'
readonly _WORKFLOW_RUN_NAME_QUEUE_REF='github.event.merge_group.head_ref'

# Prints "RUNNAME<TAB><value>" for the top-level run-name, or nothing when
# the key is absent. A block scalar (`>-`, `|`) is joined into one line.
# shellcheck disable=SC2016 # awk program; $-vars are awk's, not the shell's.
readonly _WORKFLOW_RUN_NAME_AWK='
state == 0 && /^run-name:/ {
  v = $0; sub(/^run-name:[ \t]*/, "", v)
  if (v ~ /^[>|][-+0-9]*[ \t]*(#.*)?$/) { state = 1; next }
  out = v; state = 2; exit
}
state == 1 && /^[ \t]*$/ { next }
state == 1 && /^[ \t]/ {
  t = $0; sub(/^[ \t]+/, "", t)
  out = (out == "" ? t : out " " t)
  next
}
state == 1 { state = 2; exit }
END { if (state > 0) printf "RUNNAME\t%s\n", out }
'

# _workflow_run_name_finding <file> -- print why <file> fails, or nothing.
_workflow_run_name_finding() {
  local _file="${1}" _line _value
  _line="$(awk "${_WORKFLOW_RUN_NAME_AWK}" "${_file}")"
  if [[ "${_line}" != RUNNAME$'\t'* ]]; then
    printf 'no top-level run-name'
    return 0
  fi
  _value="${_line#RUNNAME$'\t'}"
  if [[ "${_value}" != *"${_WORKFLOW_RUN_NAME_OPEN}"*"${_WORKFLOW_RUN_NAME_CLOSE}"* ]]; then
    printf 'run-name has no %s %s expression: %s' \
      "${_WORKFLOW_RUN_NAME_OPEN}" "${_WORKFLOW_RUN_NAME_CLOSE}" "${_value:-<empty>}"
    return 0
  fi
  if [[ "${_value}" != *"${_WORKFLOW_RUN_NAME_QUEUE_REF}"* ]]; then
    printf 'run-name does not name %s, so a merge queue run hides its PR: %s' \
      "${_WORKFLOW_RUN_NAME_QUEUE_REF}" "${_value}"
  fi
}

_run_workflow_run_name() {
  echo "--- Running workflow run-name lint ---"

  local _dir="${REPO_ROOT}/${_WORKFLOW_RUN_NAME_DIR_REL}"
  local -a _files=()
  local _f
  for _f in "${_dir}"/*.yaml "${_dir}"/*.yml; do
    [[ -f "${_f}" ]] || continue
    _files+=("${_f}")
  done
  if (( ${#_files[@]} == 0 )); then
    _die ci_workflow_run_name \
      "no workflow files under '${_WORKFLOW_RUN_NAME_DIR_REL}' in ${REPO_ROOT}; the lint would pass having checked nothing."
    return 1
  fi

  local _finding _bad=0
  for _f in "${_files[@]}"; do
    _finding="$(_workflow_run_name_finding "${_f}")"
    [[ -n "${_finding}" ]] || continue
    printf '%s: %s\n' "${_WORKFLOW_RUN_NAME_DIR_REL}/${_f##*/}" "${_finding}"
    _bad=$(( _bad + 1 ))
  done

  if (( _bad > 0 )); then
    _die ci_workflow_run_name \
      "${_bad} of ${#_files[@]} workflows lack a dynamic run-name. Add a top-level 'run-name:' with a \${{ }} expression naming the trigger (event, PR number and title, merge queue ref ${_WORKFLOW_RUN_NAME_QUEUE_REF}, or ref and SHA), each part with a '||' fallback so it never renders empty."
    return 1
  fi

  echo "workflow run-name lint: clean (${#_files[@]} workflows, each with a dynamic top-level run-name)"
}
