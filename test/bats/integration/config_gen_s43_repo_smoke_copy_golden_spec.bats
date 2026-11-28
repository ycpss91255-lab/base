#!/usr/bin/env bats
#
# config_gen_s43_repo_smoke_copy_golden_spec.bats -- the s43 repo_smoke_copy
# corpus against the .dockerfile / .files / .events goldens (base#2065, S43h
# of base#1776).
#
# why: Before any Go migration exists, the shell `apply_migrations`
# (dist/script/docker/lib/dockerfile_migrate.sh) is the oracle. Every
# dockerfile/config-gen/testdata/corpus/s43/s43_rsc_<case>.Dockerfile has a
# .tree side file and three goldens under testdata/golden/s43/ (same shape as
# base#2057):
#   .dockerfile  the Dockerfile bytes after apply_migrations
#   .files       `migrated_files` stdout (0 bytes when nothing was rewritten)
#   .events      one projected event per line, tab separated:
#                <body> TAB <display> [TAB matched=.. TAB available=.. TAB
#                names=.. TAB rewritten=..]
# repo_smoke_copy depends on the test/bats/smoke/ folders present in the repo,
# so <case>.tree lists them: one relative path per line, a trailing `/` is an
# empty directory, anything else an empty file (parents are created). The
# scratch directory is built from the tree, the fixture is copied there as
# `Dockerfile`, and apply_migrations runs on that relative path. stdout and
# stderr go to one raw event file, so the event order is the output order.

bats_require_minimum_version 1.5.0

setup() {
  export LOG_FORMAT=text
  load "${BATS_TEST_DIRNAME}/../unit/test_helper"
  LIB="/source/dist/script/docker/lib"
  TESTDATA="/source/dockerfile/config-gen/testdata"
  CORPUS="${TESTDATA}/corpus/s43"
  GOLDEN="${TESTDATA}/golden/s43"
}

# _project_events <raw-json-lines-file> -- same projection as base#2057.
_project_events() {
  jq -r '[.body, .attributes.display]
    + [ ("matched", "available", "names", "rewritten") as $k
        | select(.attributes[$k] != null)
        | "\($k)=\(.attributes[$k])" ]
    | join("\t")' "$1"
}

# _build_tree <tree-file> <dir> -- create the paths listed in the tree file.
_build_tree() {
  local _p
  while IFS= read -r _p || [[ -n "${_p}" ]]; do
    [[ -n "${_p}" ]] || continue
    if [[ "${_p}" == */ ]]; then
      mkdir -p -- "${2}/${_p}"
    else
      mkdir -p -- "${2}/$(dirname -- "${_p}")"
      : > "${2}/${_p}"
    fi
  done < "$1"
}

# _regen_case <case> -- build the tree, run apply_migrations on
# s43_rsc_<case>.Dockerfile and leave out.{dockerfile,files,events} in
# ${BATS_TEST_TMPDIR}/<case>/.
_regen_case() {
  local _name="s43_rsc_${1}" _d="${BATS_TEST_TMPDIR}/${1}"
  [[ -f "${CORPUS}/${_name}.Dockerfile" ]] || {
    echo "fixture missing: ${_name}.Dockerfile" >&2
    return 1
  }
  [[ -f "${CORPUS}/${_name}.tree" ]] || {
    echo "tree missing: ${_name}.tree" >&2
    return 1
  }
  mkdir -p "${_d}"
  _build_tree "${CORPUS}/${_name}.tree" "${_d}"
  cp -- "${CORPUS}/${_name}.Dockerfile" "${_d}/Dockerfile"
  (
    cd "${_d}" || exit 1
    LOG_FORMAT=json bash -c '
      source "$1/_lib.sh"; source "$1/dockerfile_migrate.sh"
      apply_migrations Dockerfile > raw.events 2>&1
      migrated_files > out.files
    ' _ "${LIB}"
  ) || return 1
  _project_events "${_d}/raw.events" > "${_d}/out.events"
  cp -- "${_d}/Dockerfile" "${_d}/out.dockerfile"
}

# _check_case <case> -- regenerate and compare each output with its golden.
_check_case() {
  local _name="s43_rsc_${1}" _d="${BATS_TEST_TMPDIR}/${1}" _e _bad=0
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

# why: `COPY test/smoke/` is replaced by one COPY per stage folder, shared first.
@test "s43 rsc golden: wholesale COPY becomes shared + per-stage COPYs" {
  run _check_case wholesale
  assert_success
}

# why: a stage with no folder of its own gets only the shared line.
@test "s43 rsc golden: stage without its own folder gets only shared" {
  run _check_case shared
  assert_success
}

# why: `.base/test/smoke/` belongs to smoke_copy, not repo_smoke_copy.
@test "s43 rsc golden: shipped .base path is handled by smoke_copy" {
  run _check_case shipped
  assert_success
}

# why: the per-stage form is the fixed point, nothing is rewritten.
@test "s43 rsc golden: per-stage form is unchanged" {
  run _check_case idem
  assert_success
}

# why: a hand-listed spec path is mapped to the folder that holds the file.
@test "s43 rsc golden: hand-listed COPY paths are remapped" {
  run _check_case hand
  assert_success
}

# why: a retired spec found in no folder needs a manual fix, stderr event first.
@test "s43 rsc golden: retired spec found nowhere reports manual fix" {
  run _check_case manual
  assert_success
}

# ── literal expectations, independent of the goldens ────────────────────────

# why: the issue gives the wholesale events as literals; pin them so a wrong
# golden cannot pass by being regenerated the same way.
@test "s43 rsc golden: wholesale events golden equals the issue's literal events" {
  run cat "${GOLDEN}/s43_rsc_wholesale.events"
  assert_success
  assert_output "$(printf '%s\n%s' \
    $'dockerfile_patched\t  Dockerfile patched: test/smoke/ -> per-stage smoke COPYs under test/bats/smoke/ (#1044)' \
    $'dockerfile_migrations_reported\t  Dockerfile migrations: 1 of 16 matched (repo_smoke_copy), 1 file(s) rewritten\tmatched=1\tavailable=16\tnames=repo_smoke_copy\trewritten=1')"
}

# why: the issue gives the wholesale Dockerfile as a literal.
@test "s43 rsc golden: wholesale dockerfile golden equals the issue's literal" {
  run cat "${GOLDEN}/s43_rsc_wholesale.dockerfile"
  assert_success
  assert_output "$(printf '%s\n%s\n%s' \
    'FROM devel AS devel-test' \
    'COPY test/bats/smoke/shared/ /smoke_test/' \
    'COPY test/bats/smoke/devel-test/ /smoke_test/')"
}

# why: a rewrite is recorded as the Dockerfile path, one line.
@test "s43 rsc golden: wholesale files golden is the single path Dockerfile" {
  run cat "${GOLDEN}/s43_rsc_wholesale.files"
  assert_output "Dockerfile"
}

# why: the issue says shared and hand share case 1's .files and .events.
@test "s43 rsc golden: shared and hand .files/.events equal wholesale's" {
  local _c _e
  for _c in shared hand; do
    for _e in files events; do
      cmp -- "${GOLDEN}/s43_rsc_${_c}.${_e}" "${GOLDEN}/s43_rsc_wholesale.${_e}"
    done
  done
}

# why: the shipped case is reported under smoke_copy (#928), not repo_smoke_copy.
@test "s43 rsc golden: shipped events literal" {
  run cat "${GOLDEN}/s43_rsc_shipped.events"
  assert_success
  assert_output "$(printf '%s\n%s' \
    $'dockerfile_patched\t  Dockerfile patched: .base/test/smoke/ -> per-stage smoke COPYs under .base/dist/test/bats/smoke/ (#928)' \
    $'dockerfile_migrations_reported\t  Dockerfile migrations: 1 of 16 matched (smoke_copy), 1 file(s) rewritten\tmatched=1\tavailable=16\tnames=smoke_copy\trewritten=1')"
}

# why: the fixed point is a no-op: 0-byte .files, one report event, dockerfile == fixture.
@test "s43 rsc golden: idem files golden is 0 bytes and events literal" {
  [[ -f "${GOLDEN}/s43_rsc_idem.files" ]]
  [[ ! -s "${GOLDEN}/s43_rsc_idem.files" ]]
  run cat "${GOLDEN}/s43_rsc_idem.events"
  assert_success
  assert_output $'dockerfile_migrations_reported\t  Dockerfile migrations: 0 of 16 matched (none), 0 file(s) rewritten\tmatched=0\tavailable=16\tnames=none\trewritten=0'
}

# why: nothing is rewritten, so the dockerfile golden must be the fixture bytes.
@test "s43 rsc golden: idem and manual dockerfile goldens equal their fixtures" {
  local _c
  for _c in idem manual; do
    cmp -- "${CORPUS}/s43_rsc_${_c}.Dockerfile" "${GOLDEN}/s43_rsc_${_c}.dockerfile"
  done
}

# why: the manual case reports the stderr event first, then the report.
@test "s43 rsc golden: manual events literal and files golden is 0 bytes" {
  [[ -f "${GOLDEN}/s43_rsc_manual.files" ]]
  [[ ! -s "${GOLDEN}/s43_rsc_manual.files" ]]
  run cat "${GOLDEN}/s43_rsc_manual.events"
  assert_success
  assert_output "$(printf '%s\n%s' \
    $'dockerfile_needs_manual_fix\t  Dockerfile still COPYs a retired test/smoke/ spec that is shipped at no single path — resolve it by hand (#1044)' \
    $'dockerfile_migrations_reported\t  Dockerfile migrations: 1 of 16 matched (repo_smoke_copy), 0 file(s) rewritten\tmatched=1\tavailable=16\tnames=repo_smoke_copy\trewritten=0')"
}

# ── the partition check ─────────────────────────────────────────────────────

# why: each rsc fixture has a .tree and exactly the three goldens, and no golden
# or tree lacks a fixture.
@test "s43 rsc golden: every fixture has its tree and three goldens and no extra" {
  local _f _stem _e _bad=0
  for _f in "${CORPUS}"/s43_rsc_*.Dockerfile; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .Dockerfile)"
    [[ -f "${CORPUS}/${_stem}.tree" ]] || {
      echo "fixture with no tree: ${_stem}.tree" >&2
      _bad=1
    }
    for _e in dockerfile files events; do
      if [[ ! -f "${GOLDEN}/${_stem}.${_e}" ]]; then
        echo "fixture with no golden: ${_stem}.${_e}" >&2
        _bad=1
      fi
    done
  done
  for _f in "${CORPUS}"/s43_rsc_*.tree; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .tree)"
    [[ -f "${CORPUS}/${_stem}.Dockerfile" ]] || {
      echo "tree with no fixture: ${_f}" >&2
      _bad=1
    }
  done
  for _f in "${GOLDEN}"/s43_rsc_*; do
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
  for _stem in wholesale shared shipped idem hand manual; do
    [[ -f "${CORPUS}/s43_rsc_${_stem}.Dockerfile" ]] || {
      echo "fixture missing: s43_rsc_${_stem}" >&2
      _bad=1
    }
  done
  (( _bad == 0 ))
}
