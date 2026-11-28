#!/usr/bin/env bats
#
# config_gen_s43_orchestrator_golden_spec.bats -- the s43 entrypoint_orchestrator
# migration corpus against the .dockerfile / .files / .events / .detect goldens
# (base#2077, S43p of base#1776).
#
# why: Before any Go migration exists, the shell
# `_migrate_entrypoint_orchestrator_detect` / `_apply`
# (dist/script/docker/lib/dockerfile_migrate.sh) are the oracle. This
# migration only notifies, it never rewrites. Every case under
# dockerfile/config-gen/testdata/corpus/s43/ is a pair:
#   s43_orch_<case>.Dockerfile     copied to <scratch>/Dockerfile
#   s43_orch_<case>.entrypoint.sh  copied to <scratch>/script/entrypoint.sh
# and has four goldens under testdata/golden/s43/:
#   .dockerfile  the Dockerfile bytes after apply (identical to the input)
#   .files       `migrated_files` stdout (0 bytes in every case)
#   .events      one event per line, <body> TAB <display> (empty when no apply)
#   .detect      the detect exit status, 0 or 1
# apply is only called when detect returns 0, as apply_migrations does.

bats_require_minimum_version 1.5.0

setup() {
  export LOG_FORMAT=text
  load "${BATS_TEST_DIRNAME}/../unit/test_helper"
  LIB="/source/dist/script/docker/lib"
  TESTDATA="/source/dockerfile/config-gen/testdata"
  CORPUS="${TESTDATA}/corpus/s43"
  GOLDEN="${TESTDATA}/golden/s43"
}

# _regen_case <case> -- run detect (and apply when detect is 0) on the case
# and leave out.{dockerfile,files,events,detect} and out.entrypoint in
# ${BATS_TEST_TMPDIR}/<case>/.
_regen_case() {
  local _name="s43_orch_${1}" _d="${BATS_TEST_TMPDIR}/${1}"
  [[ -f "${CORPUS}/${_name}.Dockerfile" && -f "${CORPUS}/${_name}.entrypoint.sh" ]] || {
    echo "fixture missing: ${_name}" >&2
    return 1
  }
  mkdir -p "${_d}/script"
  cp -- "${CORPUS}/${_name}.Dockerfile" "${_d}/Dockerfile"
  cp -- "${CORPUS}/${_name}.entrypoint.sh" "${_d}/script/entrypoint.sh"
  (
    cd "${_d}" || exit 1
    LOG_FORMAT=json bash -c '
      source "$1/_lib.sh"; source "$1/dockerfile_migrate.sh"
      : > raw.events
      _rc=0
      _migrate_entrypoint_orchestrator_detect Dockerfile || _rc=$?
      printf "%s\n" "${_rc}" > out.detect
      if (( _rc == 0 )); then
        _migrate_entrypoint_orchestrator_apply Dockerfile > raw.events 2>&1
      fi
      migrated_files > out.files
    ' _ "${LIB}"
  ) || return 1
  jq -r '[.body, .attributes.display] | join("\t")' "${_d}/raw.events" > "${_d}/out.events"
  cp -- "${_d}/Dockerfile" "${_d}/out.dockerfile"
}

# _check_case <case> -- regenerate and compare each output with its golden.
_check_case() {
  local _name="s43_orch_${1}" _d="${BATS_TEST_TMPDIR}/${1}" _e _bad=0
  for _e in dockerfile files events detect; do
    [[ -f "${GOLDEN}/${_name}.${_e}" ]] || {
      echo "golden missing: ${_name}.${_e}" >&2
      _bad=1
    }
  done
  (( _bad == 0 )) || return 1
  _regen_case "$1" || return 1
  for _e in dockerfile files events detect; do
    cmp -- "${_d}/out.${_e}" "${GOLDEN}/${_name}.${_e}" || _bad=1
  done
  # entrypoint.sh must come out unchanged too (the notice writes nothing).
  cmp -- "${_d}/script/entrypoint.sh" "${CORPUS}/${_name}.entrypoint.sh" || _bad=1
  (( _bad == 0 ))
}

# ── one test per case ───────────────────────────────────────────────────────

# why: the pre-orchestrator model is noticed: detect 0, one advisory, no rewrite.
@test "s43 orch golden: old model is noticed and nothing is rewritten" {
  run _check_case old
  assert_success
}

# why: an already migrated repo is silent.
@test "s43 orch golden: migrated repo is silent" {
  run _check_case migrated
  assert_success
}

# why: a commented ENTRYPOINT is not the live model.
@test "s43 orch golden: commented ENTRYPOINT is silent" {
  run _check_case commented
  assert_success
}

# why: an unrelated ENTRYPOINT is not this model.
@test "s43 orch golden: unrelated ENTRYPOINT is silent" {
  run _check_case unrelated
  assert_success
}

# ── literal expectations, independent of the goldens ────────────────────────

# why: the issue pins the old case as one advisory event whose display says
# nothing was changed; a wrong golden cannot pass by being regenerated alike.
@test "s43 orch golden: old events golden is one advisory line" {
  run cat "${GOLDEN}/s43_orch_old.events"
  assert_success
  [[ "${#lines[@]}" -eq 1 ]]
  [[ "${lines[0]}" == dockerfile_entrypoint_advisory$'\t'* ]]
  [[ "${lines[0]}" == *"Nothing was changed here"* ]]
}

# why: detect exit codes are 0 for old and 1 for the other three (issue table).
@test "s43 orch golden: detect goldens are 0 for old and 1 otherwise" {
  [[ "$(cat "${GOLDEN}/s43_orch_old.detect")" == "0" ]]
  local _c
  for _c in migrated commented unrelated; do
    [[ "$(cat "${GOLDEN}/s43_orch_${_c}.detect")" == "1" ]]
  done
}

# why: every .files golden is 0 bytes, and the silent cases have empty events.
@test "s43 orch golden: files goldens are 0 bytes, silent events are 0 bytes" {
  local _c
  for _c in old migrated commented unrelated; do
    [[ -f "${GOLDEN}/s43_orch_${_c}.files" ]]
    [[ ! -s "${GOLDEN}/s43_orch_${_c}.files" ]]
  done
  for _c in migrated commented unrelated; do
    [[ -f "${GOLDEN}/s43_orch_${_c}.events" ]]
    [[ ! -s "${GOLDEN}/s43_orch_${_c}.events" ]]
  done
}

# why: the notice rewrites nothing, so every .dockerfile golden is its fixture.
@test "s43 orch golden: dockerfile goldens equal their fixtures" {
  local _c
  for _c in old migrated commented unrelated; do
    cmp -- "${CORPUS}/s43_orch_${_c}.Dockerfile" "${GOLDEN}/s43_orch_${_c}.dockerfile"
  done
}

# ── the partition check ─────────────────────────────────────────────────────

# why: each orch fixture has exactly its four goldens and no golden lacks a fixture.
@test "s43 orch golden: every fixture has exactly its four goldens and no extra" {
  local _f _stem _e _bad=0
  for _f in "${CORPUS}"/s43_orch_*.Dockerfile; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .Dockerfile)"
    [[ -f "${CORPUS}/${_stem}.entrypoint.sh" ]] || {
      echo "fixture with no entrypoint.sh: ${_stem}" >&2
      _bad=1
    }
    for _e in dockerfile files events detect; do
      if [[ ! -f "${GOLDEN}/${_stem}.${_e}" ]]; then
        echo "fixture with no golden: ${_stem}.${_e}" >&2
        _bad=1
      fi
    done
  done
  for _f in "${GOLDEN}"/s43_orch_*; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}")"
    _stem="${_stem%.*}"
    case "${_f##*.}" in
      dockerfile | files | events | detect) ;;
      *) echo "unexpected golden extension: ${_f}" >&2; _bad=1 ;;
    esac
    if [[ ! -f "${CORPUS}/${_stem}.Dockerfile" ]]; then
      echo "golden with no fixture: ${_f}" >&2
      _bad=1
    fi
  done
  for _stem in old migrated commented unrelated; do
    [[ -f "${CORPUS}/s43_orch_${_stem}.Dockerfile" ]] || {
      echo "fixture missing: s43_orch_${_stem}" >&2
      _bad=1
    }
  done
  (( _bad == 0 ))
}
