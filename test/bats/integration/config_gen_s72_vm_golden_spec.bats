#!/usr/bin/env bats
#
# config_gen_s72_vm_golden_spec.bats -- the s72 corpus of version strings
# against what today's shell makes of it (base#2300, S72a of base#1807 under
# base#1395).
#
# why: Before any Go code reads a version string, the shell's reading of it is
# pinned. The corpus file testdata/corpus/s72/s72_vm_versions.txt holds one
# input per line; the golden testdata/golden/s72/s72_vm_versions.golden holds,
# per input, "<input>TAB<_vm_is_semver exit code>TAB<_vm_key output>"
# (dist/script/docker/lib/version_migrate.sh). The third column is "-" when
# the exit code is 1: _vm_key is only ever fed a value that passed
# _vm_is_semver. The spec regenerates the golden from the shell and fails on
# any byte difference, on a corpus with no golden, and on a golden with no
# corpus.

bats_require_minimum_version 1.5.0

setup() {
  load "${BATS_TEST_DIRNAME}/../unit/test_helper"
  TESTDATA="/source/dockerfile/config-gen/testdata"
  CORPUS="${TESTDATA}/corpus/s72"
  GOLDEN="${TESTDATA}/golden/s72"
  STEM=s72_vm_versions
}

# _shell_result -- print, for each line of the corpus, the golden line the
# shell yields: "<input>TAB<exit code>TAB<key or ->".
_shell_result() {
  local _in _rc _key
  while IFS= read -r _in || [[ -n "${_in}" ]]; do
    _rc=0
    _key=-
    IN="${_in}" bash -c '
      source /source/dist/script/docker/lib/version_migrate.sh
      _vm_is_semver "${IN}"
    ' || _rc=$?
    if [[ "${_rc}" -eq 0 ]]; then
      _key="$(IN="${_in}" bash -c '
        source /source/dist/script/docker/lib/version_migrate.sh
        _vm_key "${IN}"
      ')"
    fi
    printf '%s\t%s\t%s\n' "${_in}" "${_rc}" "${_key}"
  done < "${CORPUS}/${STEM}.txt"
}

# why: a missing corpus or golden would silently pin nothing.
@test "s72: the vm_versions corpus and golden exist" {
  [[ -f "${CORPUS}/${STEM}.txt" ]] || { echo "missing corpus: ${STEM}"; return 1; }
  [[ -f "${GOLDEN}/${STEM}.golden" ]] || { echo "missing golden: ${STEM}"; return 1; }
}

# why: the inputs must be the issue's own nineteen, in its order, including
# the empty line and the line with a leading space, or the golden pins other
# cases (base#2300).
@test "s72: the corpus holds the issue's nineteen inputs" {
  local _want
  _want=$'v1.2.3\n1.2.3\nv01.02.03\nv1.2.3-rc9\nv1.2.3-rc10\nv1.2.3-rc.1\n'
  _want+=$'v0.43.0\nv99999.0.1\nv0.9.7\nv0.10.0\n1.2\nv1\n\n v1.2.3\nabc\n'
  _want+=$'v1.2.x\nv1.2.3-\nv1.2.3-rc_1\n1.2.3.4\n'
  [[ -f "${CORPUS}/${STEM}.txt" ]] || { echo "missing corpus: ${STEM}"; return 1; }
  [ "$(cat -- "${CORPUS}/${STEM}.txt"; echo x)" = "${_want}x" ]
}

# why: the worked results come from the issue's table, not from the shell.
@test "s72: the golden holds the issue's results" {
  local _want _t=$'\t'
  _want="v1.2.3${_t}0${_t}000010000200003"$'\n'
  _want+="1.2.3${_t}0${_t}000010000200003"$'\n'
  _want+="v01.02.03${_t}0${_t}000010000200003"$'\n'
  _want+="v1.2.3-rc9${_t}0${_t}000010000200003"$'\n'
  _want+="v1.2.3-rc10${_t}0${_t}000010000200003"$'\n'
  _want+="v1.2.3-rc.1${_t}0${_t}000010000200003"$'\n'
  _want+="v0.43.0${_t}0${_t}000000004300000"$'\n'
  _want+="v99999.0.1${_t}0${_t}999990000000001"$'\n'
  _want+="v0.9.7${_t}0${_t}000000000900007"$'\n'
  _want+="v0.10.0${_t}0${_t}000000001000000"$'\n'
  _want+="1.2${_t}1${_t}-"$'\n'
  _want+="v1${_t}1${_t}-"$'\n'
  _want+="${_t}1${_t}-"$'\n'
  _want+=" v1.2.3${_t}1${_t}-"$'\n'
  _want+="abc${_t}1${_t}-"$'\n'
  _want+="v1.2.x${_t}1${_t}-"$'\n'
  _want+="v1.2.3-${_t}1${_t}-"$'\n'
  _want+="v1.2.3-rc_1${_t}1${_t}-"$'\n'
  _want+="1.2.3.4${_t}1${_t}-"$'\n'
  [[ -f "${GOLDEN}/${STEM}.golden" ]] || { echo "missing golden: ${STEM}"; return 1; }
  [ "$(cat -- "${GOLDEN}/${STEM}.golden"; echo x)" = "${_want}x" ]
}

# why: _vm_is_semver and _vm_key read the corpus the way the golden says; the
# shell result must match it byte for byte.
@test "s72: the shell result matches the golden" {
  [[ -f "${CORPUS}/${STEM}.txt" ]] || { echo "missing corpus: ${STEM}"; return 1; }
  [[ -f "${GOLDEN}/${STEM}.golden" ]] || { echo "missing golden: ${STEM}"; return 1; }
  _shell_result > "${BATS_TEST_TMPDIR}/got"
  cmp -- "${BATS_TEST_TMPDIR}/got" "${GOLDEN}/${STEM}.golden"
}

# why: a golden whose corpus file was deleted would stand for nothing.
@test "s72: every golden has a corpus file" {
  local _g _stem _bad=0
  for _g in "${GOLDEN}"/*.golden; do
    [[ -e "${_g}" ]] || continue
    _stem="$(basename -- "${_g}" .golden)"
    if [[ ! -f "${CORPUS}/${_stem}.txt" ]]; then
      printf 'golden with no corpus: %s\n' "${_stem}"
      _bad=1
    fi
  done
  [ "${_bad}" -eq 0 ]
}

# why: a corpus file with no golden would pin nothing; and with no files at
# all the loops above pass vacuously.
@test "s72: every corpus file has a golden" {
  local _f _stem _n=0 _bad=0
  for _f in "${CORPUS}"/*.txt; do
    [[ -e "${_f}" ]] || continue
    _n=$((_n + 1))
    _stem="$(basename -- "${_f}" .txt)"
    if [[ ! -f "${GOLDEN}/${_stem}.golden" ]]; then
      printf 'corpus with no golden: %s\n' "${_stem}"
      _bad=1
    fi
  done
  [ "${_n}" -ge 1 ] || { echo "no s72 corpus files"; return 1; }
  [ "${_bad}" -eq 0 ]
}
