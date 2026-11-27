#!/usr/bin/env bats
#
# config_gen_s43_harness_golden_spec.bats -- the s43 migration dispatcher
# corpus against the .dockerfile / .files / .events goldens (base#2055, S43b
# of base#1776).
#
# why: Before any Go migration exists, the shell `apply_migrations`
# (dist/script/docker/lib/dockerfile_migrate.sh) with migration 0
# (downstream_to_dist) is the oracle. Every
# dockerfile/config-gen/testdata/corpus/s43/s43_migrate_<case>.Dockerfile has
# three goldens under testdata/golden/s43/:
#   .dockerfile  the Dockerfile bytes after apply_migrations
#   .files       `migrated_files` stdout (one path per line; 0 bytes when
#                nothing was rewritten)
#   .events      one projected event per line, tab separated:
#                <body> TAB <display> [TAB matched=.. TAB available=.. TAB
#                names=.. TAB rewritten=..]; no timestamp, code.filepath,
#                code.lineno or thread.id (they change on every run)
# The spec regenerates all three from the shell under LOG_FORMAT=json and
# compares them byte for byte. The fixture is run as the relative path
# `Dockerfile` inside a scratch directory, so the path in `.files` is stable.
# A partition check keeps fixtures and goldens one-to-one-to-one.

bats_require_minimum_version 1.5.0

setup() {
  export LOG_FORMAT=text
  load "${BATS_TEST_DIRNAME}/../unit/test_helper"
  LIB="/source/dist/script/docker/lib"
  TESTDATA="/source/dockerfile/config-gen/testdata"
  CORPUS="${TESTDATA}/corpus/s43"
  GOLDEN="${TESTDATA}/golden/s43"
}

# _project_events <raw-json-lines-file> -- the event projection described above.
_project_events() {
  jq -r '[.body, .attributes.display]
    + [ ("matched", "available", "names", "rewritten") as $k
        | select(.attributes[$k] != null)
        | "\($k)=\(.attributes[$k])" ]
    | join("\t")' "$1"
}

# _regen_case <case> -- run apply_migrations on s43_migrate_<case>.Dockerfile
# and leave the three outputs in ${BATS_TEST_TMPDIR}/<case>/out.{dockerfile,files,events}.
_regen_case() {
  local _name="s43_migrate_${1}" _d="${BATS_TEST_TMPDIR}/${1}"
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
  local _name="s43_migrate_${1}" _d="${BATS_TEST_TMPDIR}/${1}" _e _bad=0
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

# why: two lint COPY lines are rewritten, the rest of the file is untouched.
@test "s43 migrate golden: lint rewrites both COPY sources" {
  run _check_case lint
  assert_success
}

# why: sed is global, so a RUN line is rewritten too, not only COPY.
@test "s43 migrate golden: run rewrites COPY and RUN lines" {
  run _check_case run
  assert_success
}

# why: an already-current Dockerfile is left byte for byte and nothing is reported rewritten.
@test "s43 migrate golden: current is unchanged and reports 0 matched" {
  run _check_case current
  assert_success
}

# ── literal expectations, independent of the goldens ────────────────────────

# why: the issue's table gives the lint events as literals; pin them so a
# wrong golden cannot pass by being regenerated the same way.
@test "s43 migrate golden: lint events golden equals the issue's literal events" {
  run cat "${GOLDEN}/s43_migrate_lint.events"
  assert_success
  assert_output "$(printf '%s\n%s' \
    $'dockerfile_patched\t  Dockerfile patched: .base/downstream/ -> .base/dist/ (#714)' \
    $'dockerfile_migrations_reported\t  Dockerfile migrations: 1 of 16 matched (downstream_to_dist), 1 file(s) rewritten\tmatched=1\tavailable=16\tnames=downstream_to_dist\trewritten=1')"
}

# why: the run fixture shares the lint events (issue table).
@test "s43 migrate golden: run events golden is byte-identical to lint events" {
  cmp -- "${GOLDEN}/s43_migrate_run.events" "${GOLDEN}/s43_migrate_lint.events"
}

# why: a rewrite is recorded as the Dockerfile path, one line.
@test "s43 migrate golden: lint and run files goldens are the single path Dockerfile" {
  run cat "${GOLDEN}/s43_migrate_lint.files"
  assert_output "Dockerfile"
  run cat "${GOLDEN}/s43_migrate_run.files"
  assert_output "Dockerfile"
}

# why: a no-op run is a 0-byte .files and a single report event.
@test "s43 migrate golden: current files golden is 0 bytes and events literal" {
  [[ -f "${GOLDEN}/s43_migrate_current.files" ]]
  [[ ! -s "${GOLDEN}/s43_migrate_current.files" ]]
  run cat "${GOLDEN}/s43_migrate_current.events"
  assert_success
  assert_output $'dockerfile_migrations_reported\t  Dockerfile migrations: 0 of 16 matched (none), 0 file(s) rewritten\tmatched=0\tavailable=16\tnames=none\trewritten=0'
}

# why: the current fixture is the idempotent end state, so its golden equals the fixture.
@test "s43 migrate golden: current dockerfile golden equals its fixture" {
  cmp -- "${CORPUS}/s43_migrate_current.Dockerfile" "${GOLDEN}/s43_migrate_current.dockerfile"
}

# why: no .base/downstream/ may survive in a rewritten golden, and the
# rewritten COPY source is the dist path from the issue.
@test "s43 migrate golden: rewritten goldens hold no .base/downstream/" {
  run grep -c '\.base/downstream/' "${GOLDEN}/s43_migrate_lint.dockerfile"
  assert_output "0"
  run grep -c '\.base/downstream/' "${GOLDEN}/s43_migrate_run.dockerfile"
  assert_output "0"
  run grep -x 'COPY .base/dist/script/docker/lib /lint/lib' "${GOLDEN}/s43_migrate_lint.dockerfile"
  assert_success
}

# why: a missing Dockerfile is not an error; the Go side needs rc 0, no
# migrated files and the one skip event.
@test "s43 migrate golden: a missing Dockerfile skips with one event and no files" {
  local _p="${BATS_TEST_TMPDIR}/no_such.Dockerfile"
  run -0 env LOG_FORMAT=json bash -c '
    source "$1/_lib.sh"; source "$1/dockerfile_migrate.sh"
    apply_migrations "$2" > "$3"
    migrated_files
  ' _ "${LIB}" "${_p}" "${BATS_TEST_TMPDIR}/skip.raw"
  assert_output ""
  run _project_events "${BATS_TEST_TMPDIR}/skip.raw"
  assert_success
  assert_output $'dockerfile_migration_skipped\t  no Dockerfile at '"${_p}"' — skip migrations'
  [[ "${output}" != *$'\n'* ]]
}

# ── the partition check ─────────────────────────────────────────────────────

# why: each migrate fixture must have exactly the three goldens and no
# golden may lack a fixture, so the corpus cannot drift.
@test "s43 migrate golden: every fixture has exactly its three goldens and no extra" {
  local _f _stem _e _bad=0
  for _f in "${CORPUS}"/s43_migrate_*.Dockerfile; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .Dockerfile)"
    for _e in dockerfile files events; do
      if [[ ! -f "${GOLDEN}/${_stem}.${_e}" ]]; then
        echo "fixture with no golden: ${_stem}.${_e}" >&2
        _bad=1
      fi
    done
  done
  for _f in "${GOLDEN}"/s43_migrate_*; do
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
  [[ -d "${CORPUS}" ]] || _bad=1
  # the three fixtures of this slice must exist
  for _stem in lint run current; do
    [[ -f "${CORPUS}/s43_migrate_${_stem}.Dockerfile" ]] || {
      echo "fixture missing: s43_migrate_${_stem}" >&2
      _bad=1
    }
  done
  (( _bad == 0 ))
}
