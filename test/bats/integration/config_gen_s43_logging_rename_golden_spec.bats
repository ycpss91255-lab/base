#!/usr/bin/env bats
#
# config_gen_s43_logging_rename_golden_spec.bats -- the s43 logging_rename
# (migration 4) corpus against the .dockerfile / .files / .events (and, when
# the case has a sibling entrypoint, .entrypoint) goldens (base#2061, S43f of
# base#1776).
#
# why: Before any Go migration exists, the shell
# `_migrate_logging_rename_detect` / `_migrate_logging_rename_apply`
# (dist/script/docker/lib/dockerfile_migrate.sh) are the oracle. Every
# dockerfile/config-gen/testdata/corpus/s43/s43_logrn_<case>.Dockerfile has
# these goldens under testdata/golden/s43/ (same shape as base#2057):
#   .dockerfile  the Dockerfile bytes after detect && apply
#   .files       `migrated_files` stdout (0 bytes when nothing was rewritten)
#   .events      one projected event per line, tab separated: <body> TAB <display>
#   .entrypoint  script/entrypoint.sh after apply; only for a case that has a
#                s43_logrn_<case>.entrypoint.sh fixture
# The fixture is run as the relative path `Dockerfile` in a scratch directory;
# its entrypoint fixture is copied to script/entrypoint.sh beside it.

bats_require_minimum_version 1.5.0

setup() {
  export LOG_FORMAT=text
  load "${BATS_TEST_DIRNAME}/../unit/test_helper"
  LIB="/source/dist/script/docker/lib"
  TESTDATA="/source/dockerfile/config-gen/testdata"
  CORPUS="${TESTDATA}/corpus/s43"
  GOLDEN="${TESTDATA}/golden/s43"
}

# _project_events <raw-json-lines-file> -- body and display per event.
_project_events() {
  jq -r '[.body, .attributes.display] | join("\t")' "$1"
}

# _exts_for <case> -- the golden extensions a case must have.
_exts_for() {
  local _x="dockerfile files events"
  [[ -f "${CORPUS}/s43_logrn_${1}.entrypoint.sh" ]] && _x="${_x} entrypoint"
  printf '%s' "${_x}"
}

# _regen_case <case> -- run detect && apply on s43_logrn_<case>.Dockerfile and
# leave out.{dockerfile,files,events[,entrypoint]} in ${BATS_TEST_TMPDIR}/<case>/.
_regen_case() {
  local _name="s43_logrn_${1}" _d="${BATS_TEST_TMPDIR}/${1}"
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
      if _migrate_logging_rename_detect Dockerfile; then
        _migrate_logging_rename_apply Dockerfile
      fi > raw.events
      migrated_files > out.files
    ' _ "${LIB}"
  ) || return 1
  _project_events "${_d}/raw.events" > "${_d}/out.events"
  cp -- "${_d}/Dockerfile" "${_d}/out.dockerfile"
  if [[ -f "${CORPUS}/${_name}.entrypoint.sh" ]]; then
    cp -- "${_d}/script/entrypoint.sh" "${_d}/out.entrypoint"
  fi
}

# _check_case <case> -- regenerate and compare each output with its golden.
_check_case() {
  local _name="s43_logrn_${1}" _d="${BATS_TEST_TMPDIR}/${1}" _e _bad=0
  for _e in $(_exts_for "$1"); do
    [[ -f "${GOLDEN}/${_name}.${_e}" ]] || {
      echo "golden missing: ${_name}.${_e}" >&2
      _bad=1
    }
  done
  (( _bad == 0 )) || return 1
  _regen_case "$1" || return 1
  for _e in $(_exts_for "$1"); do
    cmp -- "${_d}/out.${_e}" "${GOLDEN}/${_name}.${_e}" || _bad=1
  done
  (( _bad == 0 ))
}

# ── one test per case ───────────────────────────────────────────────────────

# why: the Dockerfile COPY alone is renamed (no sibling entrypoint).
@test "s43 logrn golden: copy case is rewritten" {
  run _check_case copy
  assert_success
}

# why: with a sibling entrypoint both files are healed.
@test "s43 logrn golden: entry case is rewritten" {
  run _check_case entry
  assert_success
}

# why: already on the new name and no entrypoint, detect is false, bytes unchanged.
@test "s43 logrn golden: new case is unchanged" {
  run _check_case new
  assert_success
}

# why: partial migration heals only the entrypoint.
@test "s43 logrn golden: partial case heals only the entrypoint" {
  run _check_case partial
  assert_success
}

# ── literal expectations, independent of the goldens ────────────────────────

# why: the issue gives the rewritten COPY line as a literal.
@test "s43 logrn golden: copy dockerfile golden equals the issue's literal" {
  run cat "${GOLDEN}/s43_logrn_copy.dockerfile"
  assert_success
  assert_output "$(printf '%s\n%s' \
    'FROM busybox AS devel' \
    'COPY --chmod=0755 .base/dist/script/docker/runtime/logging.sh /usr/local/lib/base/logging.sh')"
}

# why: the issue gives the rewritten source line as a literal.
@test "s43 logrn golden: entry entrypoint golden equals the issue's literal" {
  run cat "${GOLDEN}/s43_logrn_entry.entrypoint"
  assert_success
  assert_output "$(printf '%s\n%s\n%s' \
    '#!/usr/bin/env bash' \
    '. /usr/local/lib/base/logging.sh' \
    'exec "$@"')"
}

# why: the issue gives the event order: entrypoint first, then Dockerfile.
@test "s43 logrn golden: entry events are entrypoint_patched then dockerfile_patched" {
  run cut -f1 "${GOLDEN}/s43_logrn_entry.events"
  assert_success
  assert_output "$(printf '%s\n%s' entrypoint_patched dockerfile_patched)"
}

# why: copy-only emits just dockerfile_patched.
@test "s43 logrn golden: copy events are only dockerfile_patched" {
  run cut -f1 "${GOLDEN}/s43_logrn_copy.events"
  assert_success
  assert_output "dockerfile_patched"
}

# why: the new-name case is a no-op: no events, no files, dockerfile == fixture.
@test "s43 logrn golden: new goldens are empty and the dockerfile equals its fixture" {
  [[ -f "${GOLDEN}/s43_logrn_new.events" ]]
  [[ ! -s "${GOLDEN}/s43_logrn_new.events" ]]
  [[ -f "${GOLDEN}/s43_logrn_new.files" ]]
  [[ ! -s "${GOLDEN}/s43_logrn_new.files" ]]
  cmp -- "${CORPUS}/s43_logrn_new.Dockerfile" "${GOLDEN}/s43_logrn_new.dockerfile"
}

# why: partial leaves the Dockerfile bytes and emits only entrypoint_patched.
@test "s43 logrn golden: partial keeps the dockerfile bytes and emits only entrypoint_patched" {
  cmp -- "${CORPUS}/s43_logrn_partial.Dockerfile" "${GOLDEN}/s43_logrn_partial.dockerfile"
  run cut -f1 "${GOLDEN}/s43_logrn_partial.events"
  assert_success
  assert_output "entrypoint_patched"
  run cat "${GOLDEN}/s43_logrn_partial.entrypoint"
  assert_success
  assert_output "$(printf '%s\n%s\n%s' \
    '#!/usr/bin/env bash' \
    '. /usr/local/lib/base/logging.sh' \
    'exec "$@"')"
}

# ── the partition check ─────────────────────────────────────────────────────

# why: each logrn fixture has exactly its goldens and no golden lacks a fixture.
@test "s43 logrn golden: every fixture has exactly its goldens and no extra" {
  local _f _stem _e _bad=0 _c
  for _f in "${CORPUS}"/s43_logrn_*.Dockerfile; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .Dockerfile)"
    _c="${_stem#s43_logrn_}"
    for _e in $(_exts_for "${_c}"); do
      if [[ ! -f "${GOLDEN}/${_stem}.${_e}" ]]; then
        echo "fixture with no golden: ${_stem}.${_e}" >&2
        _bad=1
      fi
    done
  done
  for _f in "${GOLDEN}"/s43_logrn_*; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}")"
    _stem="${_stem%.*}"
    case "${_f##*.}" in
      dockerfile | files | events | entrypoint) ;;
      *) echo "unexpected golden extension: ${_f}" >&2; _bad=1 ;;
    esac
    if [[ ! -f "${CORPUS}/${_stem}.Dockerfile" ]]; then
      echo "golden with no fixture: ${_f}" >&2
      _bad=1
    fi
    if [[ "${_f##*.}" == entrypoint && ! -f "${CORPUS}/${_stem}.entrypoint.sh" ]]; then
      echo "entrypoint golden with no entrypoint fixture: ${_f}" >&2
      _bad=1
    fi
  done
  for _stem in copy entry new partial; do
    [[ -f "${CORPUS}/s43_logrn_${_stem}.Dockerfile" ]] || {
      echo "fixture missing: s43_logrn_${_stem}" >&2
      _bad=1
    }
  done
  (( _bad == 0 ))
}
