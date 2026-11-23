#!/usr/bin/env bash
#
# doc_reader_specs.sh -- the unit and integration specs that read the
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
# sorted. A spec is listed when a line of it that is not a comment does
# one of these. <root-ref> is `/source`, or a variable the spec assigns
# `/source`:
#   1. names a documentation path below <root-ref>: doc, README*,
#      CONTEXT.md, LICENSE or CHANGELOG*;
#   2. names a documentation path at the start of a word (`doc/...`,
#      `README.md`), in a spec that also assigns such a variable or changes
#      directory into the tree, so the path may be the checkout's own;
#   3. walks the tree from <root-ref>, named or entered with cd or
#      `git -C` (find, grep -r, git ls-files, git grep).
# The rules read text, so they list more specs than read a document (a
# fixture path looks the same). That is the safe direction.
#
# Fails when no spec is listed: an empty list would run nothing and read
# as a pass.

set -euo pipefail
export LC_ALL=C

_DRS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
readonly _DRS_DIR

# The documentation names, as an ERE.
readonly _DRS_DOC='(doc|README[A-Za-z.*-]*|CONTEXT\.md|LICENSE|CHANGELOG[A-Za-z.]*)'

# _drs_reads_docs <spec> -- succeeds when a rule above lists <spec>.
_drs_reads_docs() {
  local _body _vars _ref
  _body="$(grep -vE '^[[:space:]]*#' "$1")" || return 1
  _ref='/source'
  _vars="$(grep -oE '(^|[[:space:];])[A-Za-z_][A-Za-z0-9_]*="?/source"?([[:space:];]|$)' <<<"${_body}" \
    | sed -E 's/^[[:space:];]*//; s/=.*//' | sort -u | paste -sd'|')"
  [[ -z "${_vars}" ]] || _ref="(/source|\\$\{?(${_vars})\}?)"
  grep -qE "${_ref}\"?/${_DRS_DOC}([^A-Za-z0-9_]|\$)" <<<"${_body}" && return 0
  if [[ -n "${_vars}" ]] || grep -qE "cd[[:space:]]+(--[[:space:]]+)?\"?/source" <<<"${_body}"; then
    grep -qE "(^|[[:space:]\"'=(])(\./)?(doc/|README[A-Za-z.-]*\.md|CONTEXT\.md)" <<<"${_body}" && return 0
  fi
  local _walk='(find|grep[[:space:]]+(-[A-Za-z-]+[[:space:]]+)*-[A-Za-z]*[rR][A-Za-z]*|ls-files|git[[:space:]]+grep)'
  grep -qE "${_walk}.*[[:space:]\"']${_ref}/?([\"'[:space:]]|\$)" <<<"${_body}" && return 0
  grep -qE "cd[[:space:]]+(--[[:space:]]+)?\"?${_ref}/?\"?([[:space:]]|;|&).*${_walk}" <<<"${_body}" && return 0
  grep -qE "git[[:space:]]+-C[[:space:]]+\"?${_ref}/?\"?[[:space:]]+(grep|ls-files)" <<<"${_body}"
}

main() {
  local _root="${1:-${_DRS_DIR}/../..}" _spec _n=0
  _root="$(cd -- "${_root}" && pwd -P)"
  local _d
  for _d in unit integration; do
    [[ -d "${_root}/test/bats/${_d}" ]] || continue
    while IFS= read -r -d '' _spec; do
      _drs_reads_docs "${_spec}" || continue
      printf '%s\n' "${_spec#"${_root}/"}"
      _n=$((_n + 1))
    done < <(find "${_root}/test/bats/${_d}" -type f -name '*_spec.bats' -print0 | sort -z)
  done
  ((_n > 0)) || {
    printf 'doc_reader_specs: no spec under %s reads documentation\n' "${_root}/test/bats" >&2
    return 1
  }
}

main "$@"
