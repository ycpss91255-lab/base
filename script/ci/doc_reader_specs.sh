#!/usr/bin/env bash
#
# doc_reader_specs.sh -- the unit and integration specs that may read the
# checkout's own documentation, base#2110.
#
# Usage: doc_reader_specs.sh [<root>]
#
# A documentation-only pull request runs no coverage job, and these specs
# run only inside coverage, so a doc edit that breaks one of them reached
# the merge queue unseen. The doc-counts job runs this list for such a
# pull request (`test.sh --doc-readers`).
#
# Prints one path relative to <root> (default: this checkout) per line,
# sorted within each suite. A spec is listed when a line of it, or of a
# `.bash` helper under test/bats whose name it mentions, that is not a
# comment does one of these:
#   1. names a document: a path part `doc`, `.md`, README, CONTEXT,
#      LICENSE or CHANGELOG;
#   2. uses the whole tree: `/source` with nothing or a glob after it, a
#      default of `/source`, or the spec's directory climbed to the root
#      and used as it stands.
# The rules look for what is named and never for how the root is spelled,
# because a spec can spell the root in any number of ways. They list many
# specs whose document is a fixture. That is the safe direction.
#
# What they cannot see is a spec that runs a script which finds the
# documents by itself. The lint drivers are such scripts, and lint-static
# and doc-counts run them on every pull request.
#
# Fails when a spec cannot be read or a suite cannot be walked, and when no spec is listed: an empty
# list would run nothing and read as a pass.

set -euo pipefail
export LC_ALL=C

_DRS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
readonly _DRS_DIR

readonly _DRS_NAMES='(^|[^A-Za-z0-9_])doc(["'\''/[:space:]]|$)|\.md|README|CONTEXT|LICENSE|CHANGELOG'
readonly _DRS_TREE='/source/?(["'\''[:space:]);&|}]|$|/\.|\.([[:space:]]|$)|\*)|BATS_TEST_DIRNAME\}?(/\.\.)+/?(["'\''[:space:]);]|$)'

# _drs_grep <ere> <text> -- grep's own answer, with a grep that could not
#   read (2 or more) ending the run.
_drs_grep() {
  local _rc=0
  grep -qE -- "$1" <<<"$2" || _rc=$?
  ((_rc < 2)) || exit 3
  return "${_rc}"
}

# _drs_find <dir> <name glob> -- the files below <dir>, sorted; fails when
#   the walk does.
_drs_find() {
  local _found
  _found="$(find "$1" -type f -name "$2" -print)" || return 1
  [[ -z "${_found}" ]] || sort <<<"${_found}"
}

# _drs_body <file> -- its lines that are not comments.
_drs_body() {
  local _rc=0
  grep -vE '^[[:space:]]*#' -- "$1" || _rc=$?
  ((_rc < 2)) || exit 3
}

# _drs_reads <file> -- succeeds when <file> names a document or the tree.
_drs_reads() {
  local _body
  _body="$(_drs_body "$1")" || exit 3
  _drs_grep "${_DRS_NAMES}" "${_body}" || _drs_grep "${_DRS_TREE}" "${_body}"
}

main() {
  local _root="${1:-${_DRS_DIR}/../..}" _spec _helper _n=0 _d
  _root="$(cd -- "${_root}" && pwd -P)"
  # The helpers that name a document, as an ERE of their names. Only rule 1:
  # a helper's `/source` is how it finds the code it loads.
  local _helpers="" _body _files
  _files="$(_drs_find "${_root}/test/bats" '*.bash')" || exit 3
  while IFS= read -r _helper; do
    [[ -n "${_helper}" ]] || continue
    _body="$(_drs_body "${_helper}")" || exit 3
    if _drs_grep "${_DRS_NAMES}" "${_body}"; then
      _helper="${_helper##*/}"
      _helpers+="${_helpers:+|}${_helper%.bash}"
    fi
  done <<<"${_files}"
  for _d in unit integration; do
    [[ -d "${_root}/test/bats/${_d}" ]] || continue
    _files="$(_drs_find "${_root}/test/bats/${_d}" '*_spec.bats')" || exit 3
    while IFS= read -r _spec; do
      [[ -n "${_spec}" ]] || continue
      if ! _drs_reads "${_spec}"; then
        [[ -n "${_helpers}" ]] || continue
        _body="$(_drs_body "${_spec}")" || exit 3
        _drs_grep "(^|[^A-Za-z0-9_])(${_helpers})([^A-Za-z0-9_]|\$)" "${_body}" || continue
      fi
      printf '%s\n' "${_spec#"${_root}/"}"
      _n=$((_n + 1))
    done <<<"${_files}"
  done
  ((_n > 0)) || {
    printf 'doc_reader_specs: no spec under %s reads documentation\n' "${_root}/test/bats" >&2
    return 1
  }
}

main "$@"
