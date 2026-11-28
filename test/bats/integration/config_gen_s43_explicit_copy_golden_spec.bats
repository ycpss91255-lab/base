#!/usr/bin/env bats
#
# config_gen_s43_explicit_copy_golden_spec.bats -- the s43 explicit_copy
# (migration 3) corpus against the .dockerfile / .files / .events goldens
# (base#2060, S43e of base#1776).
#
# why: Before any Go migration exists, the shell
# `_migrate_explicit_copy_detect` / `_migrate_explicit_copy_apply`
# (dist/script/docker/lib/dockerfile_migrate.sh) are the oracle. Every
# dockerfile/config-gen/testdata/corpus/s43/s43_ecopy_<case>.Dockerfile has
# three goldens under testdata/golden/s43/ (same shape as base#2057):
#   .dockerfile  the Dockerfile bytes after detect && apply
#   .files       `migrated_files` stdout (0 bytes when nothing was rewritten)
#   .events      one projected event per line, tab separated:
#                <body> TAB <display>   (0 bytes when nothing was reported)
# The fixture is run as the relative path `Dockerfile` in a scratch directory.
# The prefix is s43_ecopy_ so basenames stay unique across the corpus.

bats_require_minimum_version 1.5.0

setup() {
  export LOG_FORMAT=text
  load "${BATS_TEST_DIRNAME}/../unit/test_helper"
  LIB="/source/dist/script/docker/lib"
  TESTDATA="/source/dockerfile/config-gen/testdata"
  CORPUS="${TESTDATA}/corpus/s43"
  GOLDEN="${TESTDATA}/golden/s43"
}

# _project_events <raw-json-lines-file> -- body TAB display, one per line.
_project_events() {
  jq -r '[.body, .attributes.display] | join("\t")' "$1"
}

# _regen_case <case> -- run detect && apply on s43_ecopy_<case>.Dockerfile
# and leave out.{dockerfile,files,events} in ${BATS_TEST_TMPDIR}/<case>/.
_regen_case() {
  local _name="s43_ecopy_${1}" _d="${BATS_TEST_TMPDIR}/${1}"
  [[ -f "${CORPUS}/${_name}.Dockerfile" ]] || {
    echo "fixture missing: ${_name}.Dockerfile" >&2
    return 1
  }
  mkdir -p "${_d}"
  cp -- "${CORPUS}/${_name}.Dockerfile" "${_d}/Dockerfile"
  (
    cd "${_d}" || exit 1
    LOG_FORMAT=json bash -c '
      source "$1/_lib.sh"; source "$1/dockerfile_migrate.sh"
      if _migrate_explicit_copy_detect Dockerfile; then
        _migrate_explicit_copy_apply Dockerfile
      fi > raw.events
      migrated_files > out.files
    ' _ "${LIB}"
  ) || return 1
  _project_events "${_d}/raw.events" > "${_d}/out.events"
  cp -- "${_d}/Dockerfile" "${_d}/out.dockerfile"
}

# _check_case <case> -- regenerate and compare each output with its golden.
_check_case() {
  local _name="s43_ecopy_${1}" _d="${BATS_TEST_TMPDIR}/${1}" _e _bad=0
  for _e in dockerfile files events; do
    [[ -f "${GOLDEN}/${_name}.${_e}" ]] || {
      echo "golden missing: ${_name}.${_e}" >&2
      _bad=1
    }
  done
  (( _bad == 0 )) || return 1
  _regen_case "$1" || return 1
  for _e in dockerfile files events; do
    cmp -- "${_d}/out.${_e}" "${GOLDEN}/${_name}.${_e}" || _bad=1
  done
  (( _bad == 0 ))
}

# ── one test per case ───────────────────────────────────────────────────────

# why: the single-line explicit COPY is dropped, the lib dir COPY stays.
@test "s43 ecopy golden: single-line explicit COPY is dropped" {
  run _check_case single
  assert_success
}

# why: the backslash-continued COPY block is dropped as a whole.
@test "s43 ecopy golden: multi-line backslash COPY block is dropped" {
  run _check_case multi
  assert_success
}

# why: lib and wrapper/*.sh dir COPYs need no rewrite.
@test "s43 ecopy golden: lib and wrapper dir COPYs are unchanged" {
  run _check_case noop
  assert_success
}

# ── literal expectations, independent of the goldens ────────────────────────

# why: the issue gives the single-line result: the explicit COPY is gone and
# the lib COPY is kept.
@test "s43 ecopy golden: single dockerfile golden equals the issue's literal" {
  run cat "${GOLDEN}/s43_ecopy_single.dockerfile"
  assert_success
  assert_output "$(printf '%s\n%s\n%s' \
    'FROM busybox AS lint' \
    'COPY .base/script/docker/lib /lint/lib' \
    'RUN shellcheck -S warning /lint/*.sh /lint/lib/*.sh')"
}

# why: the issue gives the multi-line result: whole block gone, lib kept.
@test "s43 ecopy golden: multi dockerfile golden equals the issue's literal" {
  run cat "${GOLDEN}/s43_ecopy_multi.dockerfile"
  assert_success
  assert_output "$(printf '%s\n%s\n%s' \
    'FROM busybox AS lint' \
    'COPY .base/script/docker/lib /lint/lib' \
    'RUN shellcheck -S warning /lint/*.sh /lint/lib/*.sh')"
}

# why: a rewrite reports dockerfile_patched exactly once.
@test "s43 ecopy golden: rewritten cases report one dockerfile_patched event" {
  local _c
  for _c in single multi; do
    run cut -f1 "${GOLDEN}/s43_ecopy_${_c}.events"
    assert_success
    assert_output "dockerfile_patched"
  done
}

# why: a rewrite is recorded as the Dockerfile path, one line.
@test "s43 ecopy golden: rewritten cases record the single path Dockerfile" {
  local _c
  for _c in single multi; do
    run cat "${GOLDEN}/s43_ecopy_${_c}.files"
    assert_success
    assert_output "Dockerfile"
  done
}

# why: detect fails on the noop shape, so nothing is rewritten, recorded or
# reported and the Dockerfile bytes equal the fixture.
@test "s43 ecopy golden: noop case detect fails and leaves no trace" {
  run bash -c "source '${LIB}/_lib.sh'; source '${LIB}/dockerfile_migrate.sh'; _migrate_explicit_copy_detect '${CORPUS}/s43_ecopy_noop.Dockerfile'"
  assert_failure
  [[ -f "${GOLDEN}/s43_ecopy_noop.files" && ! -s "${GOLDEN}/s43_ecopy_noop.files" ]]
  [[ -f "${GOLDEN}/s43_ecopy_noop.events" && ! -s "${GOLDEN}/s43_ecopy_noop.events" ]]
  cmp -- "${CORPUS}/s43_ecopy_noop.Dockerfile" "${GOLDEN}/s43_ecopy_noop.dockerfile"
}

# ── the partition check ─────────────────────────────────────────────────────

# why: each ecopy fixture has exactly the three goldens and no golden lacks a fixture.
@test "s43 ecopy golden: every fixture has exactly its three goldens and no extra" {
  local _f _stem _e _bad=0
  for _f in "${CORPUS}"/s43_ecopy_*.Dockerfile; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .Dockerfile)"
    for _e in dockerfile files events; do
      if [[ ! -f "${GOLDEN}/${_stem}.${_e}" ]]; then
        echo "fixture with no golden: ${_stem}.${_e}" >&2
        _bad=1
      fi
    done
  done
  for _f in "${GOLDEN}"/s43_ecopy_*; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}")"
    _stem="${_stem%.*}"
    case "${_f##*.}" in
      dockerfile | files | events) ;;
      *) echo "unexpected golden extension: ${_f}" >&2; _bad=1 ;;
    esac
    if [[ ! -f "${CORPUS}/${_stem}.Dockerfile" ]]; then
      echo "golden with no fixture: ${_f}" >&2
      _bad=1
    fi
  done
  for _stem in single multi noop; do
    [[ -f "${CORPUS}/s43_ecopy_${_stem}.Dockerfile" ]] || {
      echo "fixture missing: s43_ecopy_${_stem}" >&2
      _bad=1
    }
  done
  (( _bad == 0 ))
}
