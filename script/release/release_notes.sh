#!/usr/bin/env bash
#
# release_notes.sh - assemble the curated release notes for one tag, and
# REFUSE when what it assembled is not release notes.
#
# Usage:
#   release_notes.sh <tag> [changelog-dir]
#
#   <tag>            v0.42.0 / v0.42.0-rc4, with or without the leading `v`
#   changelog-dir    default: <repo>/doc/changelog
#
# Writes the body to stdout. Exit 0 = assembled; 1 = refused, with the
# reason on stderr.
#
# A final tag's notes are the union of its own section and its `-rcN`
# sections, one list per category in changelog_categories.sh order.
#
# The tag's own lead (prose above its first `### `) is published as written;
# an RC's only when it holds a `- ` entry.
#
# Refused: no section, a section in two files, no entry, fewer entries than
# the sections hold, or a body over GitHub's cap (v0.42's is 326,932).

# Where this script lives; the default changelog directory is relative to it.
_RELEASE_NOTES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" \
  &> /dev/null && pwd)"
readonly _RELEASE_NOTES_DIR

# A longer release body is rejected by the GitHub API with a 422.
readonly _RELEASE_NOTES_MAX=125000

err() { printf '[release-notes] %s\n' "$*" >&2; }

# Per-tag index of the changelog tree, filled by _index_sections:
# tag -> file, and the 0-based half-open body range within that file.
declare -A _RN_FILE=()
declare -A _RN_START=()
declare -A _RN_END=()

# The delimiter character of the fence _is_fence_delimiter last matched.
_RN_FENCE_CHAR=''

# _is_fence_delimiter <line> -- does the line open or close a fenced code
# block? Sets _RN_FENCE_CHAR to the delimiter's character when it does.
_is_fence_delimiter() {
  local _trimmed="${1#"${1%%[![:space:]]*}"}"
  if [[ "${_trimmed}" =~ ^(\`\`\`+|~~~+) ]]; then
    _RN_FENCE_CHAR="${BASH_REMATCH[1]:0:1}"
    return 0
  fi
  return 1
}

# _ends_section <line> -- the next level-2 heading, or a compare-link
# definition at column 0, ends a version section's body.
_ends_section() {
  [[ "${1}" == '## '* ]] && return 0
  [[ "${1}" =~ ^\[[^]]+\]:[[:space:]] ]] && return 0
  return 1
}

# _index_sections <dir> -- index every `## [<tag>]` section under
# <dir>/*.md. A tag found twice is fatal.
_index_sections() {
  local _dir="${1}" _file _tag _open='' _fence=''
  local -a _lines=()
  local _i
  for _file in "${_dir}"/*.md; do
    [[ -f "${_file}" ]] || continue
    mapfile -t _lines < "${_file}"
    _open=''
    _fence=''
    for (( _i = 0; _i < ${#_lines[@]}; _i++ )); do
      if _is_fence_delimiter "${_lines[_i]}"; then
        if [[ -z "${_fence}" ]]; then
          _fence="${_RN_FENCE_CHAR}"
        elif [[ "${_RN_FENCE_CHAR}" == "${_fence}" ]]; then
          _fence=''
        fi
        continue
      fi
      [[ -n "${_fence}" ]] && continue
      _ends_section "${_lines[_i]}" || continue
      if [[ -n "${_open}" ]]; then
        _RN_END["${_open}"]="${_i}"
        _open=''
      fi
      [[ "${_lines[_i]}" =~ ^##\ \[([^]]+)\] ]] || continue
      _tag="${BASH_REMATCH[1]}"
      if [[ -n "${_RN_FILE["${_tag}"]:-}" ]]; then
        err "REFUSING: '${_tag}' has a section in both" \
            "${_RN_FILE["${_tag}"]} and ${_file}. A section copied rather" \
            "than moved leaves two answers to what shipped in that tag."
        return 1
      fi
      _RN_FILE["${_tag}"]="${_file}"
      _RN_START["${_tag}"]=$(( _i + 1 ))
      _RN_END["${_tag}"]="${#_lines[@]}"
      _open="${_tag}"
    done
  done
  return 0
}

# _section_body <tag> -- the section's body lines on stdout.
_section_body() {
  local _tag="${1}" _i
  local -a _lines=()
  mapfile -t _lines < "${_RN_FILE["${_tag}"]}"
  for (( _i = _RN_START["${_tag}"]; _i < _RN_END["${_tag}"]; _i++ )); do
    printf '%s\n' "${_lines[_i]}"
  done
}

# _rc_tags <final-tag> -- the tag's `vX.Y.Z-rcN` tags, oldest first; sorted
# numerically so rc10 follows rc9.
_rc_tags() {
  local _final="${1}" _tag
  for _tag in "${!_RN_FILE[@]}"; do
    [[ "${_tag}" =~ ^"${_final}"-rc([0-9]+)$ ]] || continue
    printf '%s %s\n' "${BASH_REMATCH[1]}" "${_tag}"
  done | sort -n | cut -d' ' -f2
}

# _trim_blank_edges -- drop leading and trailing blank lines from stdin.
_trim_blank_edges() {
  local -a _buf=()
  local _line _i _first=-1 _last=-1
  while IFS= read -r _line; do
    _buf+=("${_line}")
    if [[ -n "${_line// }" ]]; then
      [[ "${_first}" -lt 0 ]] && _first=$(( ${#_buf[@]} - 1 ))
      _last=$(( ${#_buf[@]} - 1 ))
    fi
  done
  if [[ "${_first}" -ge 0 ]]; then
    for (( _i = _first; _i <= _last; _i++ )); do
      printf '%s\n' "${_buf[_i]}"
    done
  fi
}

# _trim_trailing_blanks -- drop trailing blank lines from stdin.
_trim_trailing_blanks() {
  local -a _buf=()
  local _line _i _last=-1
  while IFS= read -r _line; do
    _buf+=("${_line}")
    [[ -n "${_line// }" ]] && _last=$(( ${#_buf[@]} - 1 ))
  done
  for (( _i = 0; _i <= _last; _i++ )); do
    printf '%s\n' "${_buf[_i]}"
  done
}

# _assemble <tag>... -- merge the given sections, first tag leading, into
# one lead paragraph plus one list per category, on stdout.
_assemble() {
  local -a _tags=("$@")
  local -A _bucket=()
  local -a _order=()
  local -a _lead=() _leads=()
  local _tag _line _current='' _first=1 _key _fence=''
  local _lead_entries=0 _lead_text=''
  local -a _body=()

  for _tag in "${_tags[@]}"; do
    mapfile -t _body < <(_section_body "${_tag}")
    _current=''
    _fence=''
    _lead=()
    _lead_entries=0
    for _line in "${_body[@]}"; do
      if _is_fence_delimiter "${_line}"; then
        if [[ -z "${_fence}" ]]; then
          _fence="${_RN_FENCE_CHAR}"
        elif [[ "${_RN_FENCE_CHAR}" == "${_fence}" ]]; then
          _fence=''
        fi
      fi
      if [[ -z "${_fence}" ]] && [[ "${_line}" == '### '* ]]; then
        _current="${_line#\#\#\# }"
        _current="${_current%"${_current##*[![:space:]]}"}"
        if [[ -z "${_bucket["${_current}"]+set}" ]]; then
          _bucket["${_current}"]=''
          _order+=("${_current}")
        fi
        continue
      fi
      if [[ -z "${_current}" ]]; then
        _lead+=("${_line}")
        # Fence state ignored, as in _count_entries.
        if [[ "${_line}" == '- '* ]]; then
          _lead_entries=$(( _lead_entries + 1 ))
        fi
        continue
      fi
      _bucket["${_current}"]+="${_line}"$'\n'
    done

    # The first section's lead is kept whatever it holds, a later one's only
    # with an entry. Tests the text: _lead is never empty, only blank lines.
    _lead_text=''
    if [[ "${#_lead[@]}" -gt 0 ]] \
      && { [[ "${_first}" -eq 1 ]] || [[ "${_lead_entries}" -gt 0 ]]; }; then
      _lead_text="$(printf '%s\n' "${_lead[@]}" | _trim_blank_edges)"
    fi
    [[ -n "${_lead_text}" ]] && _leads+=("${_lead_text}")
    _first=0
  done

  local _i
  for (( _i = 0; _i < ${#_leads[@]}; _i++ )); do
    printf '%s\n' "${_leads[_i]}"
    printf '\n'
  done

  # Roster order first, then other headings in first-seen order.
  local -a _emitted=()
  for _key in "${CHANGELOG_CATEGORIES[@]}"; do
    [[ -n "${_bucket["${_key}"]+set}" ]] || continue
    _emit_category "${_key}" "${_bucket["${_key}"]}"
    _emitted+=("${_key}")
  done
  for _key in "${_order[@]}"; do
    _in_list "${_key}" "${_emitted[@]}" && continue
    _emit_category "${_key}" "${_bucket["${_key}"]}"
    _emitted+=("${_key}")
  done
}

# _in_list <needle> <haystack>... -- is the needle in the list?
_in_list() {
  local _needle="${1}" _item
  shift
  for _item in "$@"; do
    [[ "${_item}" == "${_needle}" ]] && return 0
  done
  return 1
}

# _count_entries -- how many `- ` entries at column 0 stdin carries. Ignores
# fences, unlike the merge it checks; an over-count can only refuse early.
_count_entries() {
  local _line _n=0
  while IFS= read -r _line; do
    [[ "${_line}" == '- '* ]] && _n=$(( _n + 1 ))
  done
  printf '%s' "${_n}"
}

# _emit_category <name> <body> -- one heading and its merged list.
_emit_category() {
  printf '### %s\n' "${1}"
  printf '%s' "${2}" | _trim_trailing_blanks
  printf '\n'
}

main() {
  # Strict mode here, not at file scope: the file is sourceable.
  set -euo pipefail

  local _tag="${1:-}"
  if [[ -z "${_tag}" ]]; then
    err "usage: release_notes.sh <tag> [changelog-dir]"
    return 2
  fi
  [[ "${_tag}" == v* ]] || _tag="v${_tag}"
  local _dir="${2:-${_RELEASE_NOTES_DIR}/../../doc/changelog}"
  if [[ ! -d "${_dir}" ]]; then
    err "REFUSING: no changelog directory at ${_dir}."
    return 1
  fi

  # shellcheck source=script/release/changelog_categories.sh
  source "${_RELEASE_NOTES_DIR}/changelog_categories.sh"

  _index_sections "${_dir}" || return 1
  if [[ -z "${_RN_FILE["${_tag}"]:-}" ]]; then
    err "REFUSING: no '## [${_tag}]' section under ${_dir}." \
        "The tag's notes would have been empty, and an empty body ships a" \
        "release page carrying only GitHub's autogenerated PR titles."
    return 1
  fi

  local -a _sources=("${_tag}")
  if [[ "${_tag}" != *-* ]]; then
    local _rc
    while IFS= read -r _rc; do
      [[ -n "${_rc}" ]] && _sources+=("${_rc}")
    done < <(_rc_tags "${_tag}")
  fi

  local _notes
  _notes="$(_assemble "${_sources[@]}")"
  if ! grep -q '^- ' <<< "${_notes}"; then
    err "REFUSING: the assembled notes for ${_tag} carry no entry." \
        "Sections read: ${_sources[*]}. A promoted release whose section" \
        "only points at its RCs needs those RC sections present to union."
    return 1
  fi

  # Every entry the sections hold must reach the body.
  local _source_entries=0 _emitted_entries _rc_entries
  local _source
  for _source in "${_sources[@]}"; do
    _rc_entries="$(_section_body "${_source}" | _count_entries)"
    _source_entries=$(( _source_entries + _rc_entries ))
  done
  _emitted_entries="$(_count_entries <<< "${_notes}")"
  if (( _emitted_entries < _source_entries )); then
    err "REFUSING: the assembled notes for ${_tag} carry" \
        "${_emitted_entries} of the ${_source_entries} entry bullets their" \
        "sections hold. Sections read: ${_sources[*]}. The merge files" \
        "entries under the category heading above them, so an entry it" \
        "could not place is an entry nobody is told is missing -- and the" \
        "release job publishes this body alone" \
        "(generate_release_notes: false), so there is no second source for" \
        "it. Fix the assembler, not the changelog."
    return 1
  fi
  # Bytes, which is at least the character count GitHub caps.
  local _size
  _size="$(LC_ALL=C printf '%s' "${_notes}" | wc -c)"
  if (( _size > _RELEASE_NOTES_MAX )); then
    err "REFUSING: the assembled notes for ${_tag} are ${_size} bytes," \
        "over GitHub's ${_RELEASE_NOTES_MAX}-character release body limit." \
        "Sections read: ${_sources[*]}. action-gh-release would reject this" \
        "with a 422 at tag push, after every gate has passed. Truncating" \
        "silently is not the alternative: a release page missing entries" \
        "nobody was told were dropped is the failure this script exists to" \
        "stop. Shorten the entries -- the 700-character cap the changelog" \
        "lint applies to [Unreleased] keeps a release written under it well" \
        "clear of this."
    return 1
  fi
  printf '%s\n' "${_notes}"
}

if [[ "${BASH_SOURCE[0]:-}" == "${0:-}" ]]; then
  main "$@"
fi
