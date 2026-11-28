#!/usr/bin/env bats
#
# config_gen_s43_runtime_moved_files_golden_spec.bats -- the s43 runtime_moved_files
# migration corpus against the .dockerfile / .files / .events goldens
# (base#2069, S43j of base#1776).
#
# why: Before any Go migration exists, the shell `apply_migrations`
# (dist/script/docker/lib/dockerfile_migrate.sh) is the oracle. Every
# dockerfile/config-gen/testdata/corpus/s43/s43_rmove_<case>.Dockerfile has
# three goldens under testdata/golden/s43/ (same shape as base#2055):
#   .dockerfile  the Dockerfile bytes after apply_migrations
#   .files       `migrated_files` stdout (0 bytes when nothing was rewritten)
#   .events      one projected event per line, tab separated:
#                <body> TAB <display> [TAB matched=.. TAB available=.. TAB
#                names=.. TAB rewritten=..]
# The fixture is run as the relative path `Dockerfile` in a scratch directory.
# The prefix is s43_rmove_, not s43_migrate_ (that is the base#2055 partition; s43_wcopy_ is base#2057).

bats_require_minimum_version 1.5.0

setup() {
  export LOG_FORMAT=text
  load "${BATS_TEST_DIRNAME}/../unit/test_helper"
  LIB="/source/dist/script/docker/lib"
  TESTDATA="/source/dockerfile/config-gen/testdata"
  CORPUS="${TESTDATA}/corpus/s43"
  GOLDEN="${TESTDATA}/golden/s43"
}

# _project_events <raw-json-lines-file> -- same projection as base#2055.
_project_events() {
  jq -r '[.body, .attributes.display]
    + [ ("matched", "available", "names", "rewritten") as $k
        | select(.attributes[$k] != null)
        | "\($k)=\(.attributes[$k])" ]
    | join("\t")' "$1"
}

# _regen_case <case> -- run apply_migrations on s43_rmove_<case>.Dockerfile
# and leave out.{dockerfile,files,events} in ${BATS_TEST_TMPDIR}/<case>/.
_regen_case() {
  local _name="s43_rmove_${1}" _d="${BATS_TEST_TMPDIR}/${1}"
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
      apply_migrations Dockerfile > raw.events
      migrated_files > out.files
    ' _ "${LIB}"
  ) || return 1
  _project_events "${_d}/raw.events" > "${_d}/out.events"
  cp -- "${_d}/Dockerfile" "${_d}/out.dockerfile"
}

# _check_case <case> -- regenerate and compare each output with its golden.
_check_case() {
  local _name="s43_rmove_${1}" _d="${BATS_TEST_TMPDIR}/${1}" _e _bad=0
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

# why: smoke.sh named in a commented COPY is rewritten too.
@test "s43 rmove golden: smoke.sh source is rewritten" {
  run _check_case smoke
  assert_success
}

# why: entrypoint.sh at the pre-dist path goes through flat_to_dist, then this migration.
@test "s43 rmove golden: entrypoint.sh source is rewritten" {
  run _check_case entry
  assert_success
}

# why: a whole-directory COPY names neither file, nothing is rewritten.
@test "s43 rmove golden: whole-directory COPY is unchanged" {
  run _check_case dist
  assert_success
}

# ── literal expectations, independent of the goldens ────────────────────────

# why: the issue gives event A as literals.
@test "s43 rmove golden: smoke events golden equals the issue's literal events" {
  run cat "${GOLDEN}/s43_rmove_smoke.events"
  assert_success
  assert_output "$(printf '%s\n%s' \
    $'dockerfile_patched\t  Dockerfile patched: runtime/{entrypoint,smoke}.sh moved out of the helper dir (#971)' \
    $'dockerfile_migrations_reported\t  Dockerfile migrations: 1 of 16 matched (runtime_moved_files), 1 file(s) rewritten\tmatched=1\tavailable=16\tnames=runtime_moved_files\trewritten=1')"
}

# why: the issue gives event B as literals (flat_to_dist first).
@test "s43 rmove golden: entry events golden equals the issue's literal events" {
  run cat "${GOLDEN}/s43_rmove_entry.events"
  assert_success
  assert_output "$(printf '%s\n%s\n%s' \
    $'dockerfile_patched\t  Dockerfile patched: flat .base/{config,script} -> .base/dist/ (#915)' \
    $'dockerfile_patched\t  Dockerfile patched: runtime/{entrypoint,smoke}.sh moved out of the helper dir (#971)' \
    $'dockerfile_migrations_reported\t  Dockerfile migrations: 2 of 16 matched (flat_to_dist runtime_moved_files), 1 file(s) rewritten\tmatched=2\tavailable=16\tnames=flat_to_dist runtime_moved_files\trewritten=1')"
}

# why: the issue gives the rewritten second lines as literals.
@test "s43 rmove golden: smoke dockerfile golden equals the issue's literal" {
  run cat "${GOLDEN}/s43_rmove_smoke.dockerfile"
  assert_success
  assert_output "$(printf '%s\n%s' \
    'FROM busybox AS runtime-test' \
    '# COPY .base/dist/test/bats/smoke/smoke.sh /usr/local/lib/base/smoke.sh')"
}

@test "s43 rmove golden: entry dockerfile golden equals the issue's literal" {
  run cat "${GOLDEN}/s43_rmove_entry.dockerfile"
  assert_success
  assert_output "$(printf '%s\n%s' \
    'FROM busybox AS devel' \
    'COPY --chmod=0755 .base/dist/dockerfile/entrypoint.sh /entrypoint.sh')"
}

# why: a rewrite is recorded as the Dockerfile path, one line.
@test "s43 rmove golden: rewritten cases' files golden is the single path Dockerfile" {
  local _c
  for _c in smoke entry; do
    run cat "${GOLDEN}/s43_rmove_${_c}.files"
    assert_output "Dockerfile"
  done
}

# why: event C, 0-byte .files, dockerfile == fixture.
@test "s43 rmove golden: dist files golden is 0 bytes and events literal" {
  [[ -f "${GOLDEN}/s43_rmove_dist.files" ]]
  [[ ! -s "${GOLDEN}/s43_rmove_dist.files" ]]
  run cat "${GOLDEN}/s43_rmove_dist.events"
  assert_success
  assert_output $'dockerfile_migrations_reported\t  Dockerfile migrations: 0 of 16 matched (none), 0 file(s) rewritten\tmatched=0\tavailable=16\tnames=none\trewritten=0'
}

@test "s43 rmove golden: dist dockerfile golden equals its fixture" {
  cmp -- "${CORPUS}/s43_rmove_dist.Dockerfile" "${GOLDEN}/s43_rmove_dist.dockerfile"
}

# ── the partition check ─────────────────────────────────────────────────────

# why: each rmove fixture has exactly the three goldens and no golden lacks a fixture.
@test "s43 rmove golden: every fixture has exactly its three goldens and no extra" {
  local _f _stem _e _bad=0
  for _f in "${CORPUS}"/s43_rmove_*.Dockerfile; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .Dockerfile)"
    for _e in dockerfile files events; do
      if [[ ! -f "${GOLDEN}/${_stem}.${_e}" ]]; then
        echo "fixture with no golden: ${_stem}.${_e}" >&2
        _bad=1
      fi
    done
  done
  for _f in "${GOLDEN}"/s43_rmove_*; do
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
  for _stem in smoke entry dist; do
    [[ -f "${CORPUS}/s43_rmove_${_stem}.Dockerfile" ]] || {
      echo "fixture missing: s43_rmove_${_stem}" >&2
      _bad=1
    }
  done
  (( _bad == 0 ))
}
