#!/usr/bin/env bats
#
# Spec for doc/guide/bridge-call-sites.md -- the inventory that maps every
# toml_bridge_parse / toml_bridge_merge call site under dist/ to the Go
# config-gen command and slice issue that replaces it (base#1939, part of
# base#1395).
#
# why: the Go config-gen path replaces bridge call sites one by one while both
# paths coexist; without an inventory, progress is only answerable by grep.
# The spec scans dist/ for non-comment call sites outside toml_bridge.sh and
# compares the `file:line` set with the first column of the inventory table.
# Expected rows below are the worked literals from the issue, not recomputed
# from the scan.

setup() {
  export LOG_FORMAT=text
  load "${BATS_TEST_DIRNAME}/test_helper"

  ROOT="/source"
  DOC_REL="doc/guide/bridge-call-sites.md"
  LIB_REL="dist/script/docker/lib"
  SCRATCH="$(mktemp -d)"
}

teardown() {
  [[ -n "${SCRATCH:-}" ]] && rm -rf "${SCRATCH}"
  return 0
}

# _scan_sites ROOT -> sorted unique `file:line` of call sites under ROOT/dist
# (lib-relative path), skipping comment lines and toml_bridge.sh itself.
_scan_sites() {
  local _root="${1}"
  ( cd "${_root}/${LIB_REL}" \
    && grep -rnE '^[^#]*toml_bridge_(parse|merge)' . \
      | grep -v '^\./toml_bridge\.sh:' \
      | sed -E 's#^\./##; s#^([^:]+:[0-9]+):.*#\1#' \
      | sort -u )
}

# _doc_sites DOC -> every `file:line` first-column cell, in order (dups kept).
_doc_sites() {
  local _doc="${1}"
  grep -E '^\|[[:space:]]*`[^`]+:[0-9]+`' "${_doc}" \
    | sed -E 's#^\|[[:space:]]*`([^`]+:[0-9]+)`.*#\1#'
}

# _check ROOT -> 0 when the doc and the scan agree; else prints the
# offending `file:line` values (missing / stale / duplicate) and returns 1.
_check() {
  local _root="${1}" _doc _scan _listed _rc=0
  _doc="${_root}/${DOC_REL}"
  if [[ ! -f "${_doc}" ]]; then
    echo "missing inventory: ${DOC_REL}"
    return 1
  fi
  _scan="$(_scan_sites "${_root}")"
  _listed="$(_doc_sites "${_doc}")"
  local _x
  while IFS= read -r _x; do
    [[ -z "${_x}" ]] && continue
    grep -qxF "${_x}" <<<"${_listed}" || { echo "unlisted call site: ${_x}"; _rc=1; }
  done <<<"${_scan}"
  while IFS= read -r _x; do
    [[ -z "${_x}" ]] && continue
    grep -qxF "${_x}" <<<"${_scan}" || { echo "stale row: ${_x}"; _rc=1; }
  done <<<"$(sort -u <<<"${_listed}")"
  while IFS= read -r _x; do
    [[ -z "${_x}" ]] && continue
    echo "duplicate row: ${_x}"; _rc=1
  done <<<"$(sort <<<"${_listed}" | uniq -d)"
  return "${_rc}"
}

# Copy the real lib + inventory into SCRATCH so a case can mutate them.
_mk_scratch() {
  mkdir -p "${SCRATCH}/${LIB_REL}" "${SCRATCH}/doc/guide"
  cp -r "${ROOT}/${LIB_REL}/." "${SCRATCH}/${LIB_REL}/"
  cp "${ROOT}/${DOC_REL}" "${SCRATCH}/${DOC_REL}"
}

@test "inventory doc exists" {
  [ -f "${ROOT}/${DOC_REL}" ]
}

@test "the real tree and the inventory agree" {
  run _check "${ROOT}"
  [ "${status}" -eq 0 ] || { echo "${output}"; false; }
}

@test "each known call site has exactly one row with its slice" {
  local _row
  while IFS='|' read -r _loc _slice; do
    _row="$(grep -E "^\|[[:space:]]*\`${_loc}\`" "${ROOT}/${DOC_REL}")"
    [ "$(wc -l <<<"${_row}")" -eq 1 ] || { echo "rows for ${_loc}: ${_row}"; false; }
    [[ "${_row}" == *"${_slice}"* ]] || { echo "${_loc}: want ${_slice}, got ${_row}"; false; }
  done <<'EOF'
conf.sh:189|#1870
conf.sh:600|#1870
conf.sh:2234|#1883
conf.sh:2251|#1883
conf.sh:2356|#1883
setup_conf.sh:338|#1872
setup_cmd.sh:164|#1871
config_summary.sh:267|#1881
dockerfile_migrate.sh:594|#1882
ini_to_toml_migrate.sh:218|#1452
EOF
}

@test "config-gen command and status columns are never empty" {
  local _line _n=0
  while IFS= read -r _line; do
    _n=$((_n + 1))
    # columns: file:line | call | command | slice | status
    local _cmd _status
    _cmd="$(awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$4); print $4}' <<<"${_line}")"
    _status="$(awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$6); print $6}' <<<"${_line}")"
    [ -n "${_cmd}" ] || { echo "empty command: ${_line}"; false; }
    [ -n "${_status}" ] || { echo "empty status: ${_line}"; false; }
  done < <(grep -E '^\|[[:space:]]*`[^`]+:[0-9]+`' "${ROOT}/${DOC_REL}")
  [ "${_n}" -eq 10 ]
}

@test "an unlisted call site fails the spec and names its file:line" {
  _mk_scratch
  run _check "${SCRATCH}"
  [ "${status}" -eq 0 ] || { echo "precondition: ${output}"; false; }
  printf 'toml_bridge_parse x --kv\n' >> "${SCRATCH}/${LIB_REL}/conf.sh"
  local _n
  _n="$(wc -l < "${SCRATCH}/${LIB_REL}/conf.sh")"
  run _check "${SCRATCH}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"conf.sh:${_n}"* ]]
}

@test "a stale row fails the spec and names its file:line" {
  _mk_scratch
  run _check "${SCRATCH}"
  [ "${status}" -eq 0 ] || { echo "precondition: ${output}"; false; }
  # shift every conf.sh line down by one so the listed lines no longer match
  sed -i '1i # shift' "${SCRATCH}/${LIB_REL}/conf.sh"
  run _check "${SCRATCH}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"conf.sh:189"* ]]
}

@test "a duplicate row fails the spec" {
  _mk_scratch
  run _check "${SCRATCH}"
  [ "${status}" -eq 0 ] || { echo "precondition: ${output}"; false; }
  local _row
  _row="$(grep -E '^\|[[:space:]]*`setup_cmd.sh:164`' "${SCRATCH}/${DOC_REL}")"
  [ -n "${_row}" ] || { echo "precondition: no setup_cmd.sh:164 row"; false; }
  printf '%s\n' "${_row}" >> "${SCRATCH}/${DOC_REL}"
  run _check "${SCRATCH}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"setup_cmd.sh:164"* ]]
}
