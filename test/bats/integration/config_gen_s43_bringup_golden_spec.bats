#!/usr/bin/env bats
#
# config_gen_s43_bringup_golden_spec.bats -- the s43 bringup_residue
# migration corpus against the .dockerfile / .files / .events goldens
# (base#2078, S43q of base#1776).
#
# why: Before any Go migration exists, the shell `apply_migrations`
# (dist/script/docker/lib/dockerfile_migrate.sh) is the oracle. Every
# dockerfile/config-gen/testdata/corpus/s43/s43_bringup_<case>.Dockerfile has
# three goldens under testdata/golden/s43/ (same shape as base#2057):
#   .dockerfile  the Dockerfile bytes after apply_migrations
#   .files       `migrated_files` stdout (0 bytes when nothing was rewritten)
#   .events      one projected event per line: <body> TAB <display>
# bringup_residue reads script/entrypoint.sh next to the Dockerfile, so a case
# may also have s43_bringup_<case>.entrypoint.sh, copied to script/entrypoint.sh
# in the scratch directory. The Dockerfile is run as the relative path
# `Dockerfile`. The prefix is s43_bringup_ (corpus basenames must be unique).

bats_require_minimum_version 1.5.0

setup() {
  export LOG_FORMAT=text
  load "${BATS_TEST_DIRNAME}/../unit/test_helper"
  LIB="/source/dist/script/docker/lib"
  TESTDATA="/source/dockerfile/config-gen/testdata"
  CORPUS="${TESTDATA}/corpus/s43"
  GOLDEN="${TESTDATA}/golden/s43"
}

# _project_events <raw-json-lines-file> -- <body> TAB <display>.
_project_events() {
  jq -r '[.body, .attributes.display] | join("\t")' "$1"
}

# _regen_case <case> -- run apply_migrations on s43_bringup_<case>.Dockerfile
# and leave out.{dockerfile,files,events} in ${BATS_TEST_TMPDIR}/<case>/.
_regen_case() {
  local _name="s43_bringup_${1}" _d="${BATS_TEST_TMPDIR}/${1}"
  [[ -f "${CORPUS}/${_name}.Dockerfile" ]] || {
    echo "fixture missing: ${_name}.Dockerfile" >&2
    return 1
  }
  mkdir -p "${_d}/script"
  cp -- "${CORPUS}/${_name}.Dockerfile" "${_d}/Dockerfile"
  if [[ -f "${CORPUS}/${_name}.entrypoint.sh" ]]; then
    cp -- "${CORPUS}/${_name}.entrypoint.sh" "${_d}/script/entrypoint.sh"
  fi
  (
    cd "${_d}" || exit 1
    LOG_FORMAT=json bash -c '
      source "$1/_lib.sh"; source "$1/dockerfile_migrate.sh"
      apply_migrations Dockerfile > raw.events
      migrated_files > out.files
    ' _ "${LIB}"
  ) || return 1
  _project_events "${_d}/raw.events" > "${_d}/out.events"
  cp -- "${_d}/Dockerfile" "${_d}/out.dockerfile"
}

# _check_case <case> -- regenerate and compare each output with its golden.
_check_case() {
  local _name="s43_bringup_${1}" _d="${BATS_TEST_TMPDIR}/${1}" _e _bad=0
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

# why: a surviving exec in the bringup fires mid-source (advisory only).
@test "s43 bringup golden: exec in the bringup is advised" {
  run _check_case exec
  assert_success
}

# why: a re-sourced orchestrator helper runs twice (advisory only).
@test "s43 bringup golden: a re-sourced helper is advised" {
  run _check_case plumb
  assert_success
}

# why: a clean bringup is the steady state, no advisory.
@test "s43 bringup golden: a clean bringup is silent" {
  run _check_case clean
  assert_success
}

# why: no bringup file at all is a supported shape, no advisory.
@test "s43 bringup golden: no bringup file is silent" {
  run _check_case nobring
  assert_success
}

# ── literal expectations from the issue, independent of the goldens ────────

# why: the issue gives the exec events as literals; pin them so a wrong golden
# cannot pass by being regenerated the same way.
@test "s43 bringup golden: exec events golden equals the issue's literal events" {
  run cat "${GOLDEN}/s43_bringup_exec.events"
  assert_success
  assert_output "$(printf '%s\n%s' \
    $'entrypoint_advisory\t  script/entrypoint.sh still execs, but the ENTRYPOINT is base\'s orchestrator, which SOURCES it -- the exec fires mid-source and the watchdog never arms. Drop it; the orchestrator owns the final exec. Nothing was changed here.' \
    $'dockerfile_migrations_reported\t  Dockerfile migrations: 1 of 16 matched (bringup_residue), 0 file(s) rewritten')"
}

# why: the issue gives the plumb events as literals.
@test "s43 bringup golden: plumb events golden equals the issue's literal events" {
  run cat "${GOLDEN}/s43_bringup_plumb.events"
  assert_success
  assert_output "$(printf '%s\n%s' \
    $'entrypoint_advisory\t  script/entrypoint.sh still sources a /usr/local/lib/base/ helper the orchestrator already sources, so it runs twice (a second per-start log, or a second watchdog). Drop the source line. Nothing was changed here.' \
    $'dockerfile_migrations_reported\t  Dockerfile migrations: 1 of 16 matched (bringup_residue), 0 file(s) rewritten')"
}

# why: clean and nobring report no match, a single line each.
@test "s43 bringup golden: clean and nobring events goldens equal the issue's literal" {
  local _c
  for _c in clean nobring; do
    run cat "${GOLDEN}/s43_bringup_${_c}.events"
    assert_success
    assert_output $'dockerfile_migrations_reported\t  Dockerfile migrations: 0 of 16 matched (none), 0 file(s) rewritten'
  done
}

# why: the migration is warn-only, so every .files golden is 0 bytes and every
# .dockerfile golden is the fixture bytes.
@test "s43 bringup golden: nothing is rewritten in any case" {
  local _c
  for _c in exec plumb clean nobring; do
    [[ -f "${GOLDEN}/s43_bringup_${_c}.files" ]]
    [[ ! -s "${GOLDEN}/s43_bringup_${_c}.files" ]]
    cmp -- "${CORPUS}/s43_bringup_${_c}.Dockerfile" "${GOLDEN}/s43_bringup_${_c}.dockerfile"
  done
}

# ── the partition check ─────────────────────────────────────────────────────

# why: each bringup fixture has exactly the three goldens and no golden lacks a fixture.
@test "s43 bringup golden: every fixture has exactly its three goldens and no extra" {
  local _f _stem _e _bad=0
  for _f in "${CORPUS}"/s43_bringup_*.Dockerfile; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .Dockerfile)"
    for _e in dockerfile files events; do
      if [[ ! -f "${GOLDEN}/${_stem}.${_e}" ]]; then
        echo "fixture with no golden: ${_stem}.${_e}" >&2
        _bad=1
      fi
    done
  done
  for _f in "${GOLDEN}"/s43_bringup_*; do
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
  for _stem in exec plumb clean nobring; do
    [[ -f "${CORPUS}/s43_bringup_${_stem}.Dockerfile" ]] || {
      echo "fixture missing: s43_bringup_${_stem}" >&2
      _bad=1
    }
  done
  (( _bad == 0 ))
}
