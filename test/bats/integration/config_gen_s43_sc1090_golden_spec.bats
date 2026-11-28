#!/usr/bin/env bats
#
# config_gen_s43_sc1090_golden_spec.bats -- the s43 sc1090 (migration 6)
# corpus against the .dockerfile / .entrypoint / .files / .events goldens
# (base#2073, S43m of base#1776).
#
# why: Before any Go migration exists, the shell `apply_migrations`
# (dist/script/docker/lib/dockerfile_migrate.sh, _migrate_sc1090_detect /
# _migrate_sc1090_apply) is the oracle. Every
# dockerfile/config-gen/testdata/corpus/s43/s43_sc1090_<case>.Dockerfile has a
# sibling s43_sc1090_<case>.entrypoint.sh and four goldens under
# testdata/golden/s43/ (same shape as base#2057, plus .entrypoint):
#   .dockerfile  the Dockerfile bytes after apply_migrations
#   .entrypoint  the script/entrypoint.sh bytes after apply_migrations
#   .files       `migrated_files` stdout (0 bytes when nothing was rewritten)
#   .events      one projected event per line, tab separated:
#                <body> TAB <display> [TAB matched=.. TAB available=.. TAB
#                names=.. TAB rewritten=..]
# The fixture is run as the relative path `Dockerfile` in a scratch directory
# with the entrypoint copied to script/entrypoint.sh.

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

# _regen_case <case> -- run apply_migrations on s43_sc1090_<case>.Dockerfile
# with its entrypoint at script/entrypoint.sh and leave
# out.{dockerfile,entrypoint,files,events} in ${BATS_TEST_TMPDIR}/<case>/.
_regen_case() {
  local _name="s43_sc1090_${1}" _d="${BATS_TEST_TMPDIR}/${1}"
  [[ -f "${CORPUS}/${_name}.Dockerfile" ]] || {
    echo "fixture missing: ${_name}.Dockerfile" >&2
    return 1
  }
  [[ -f "${CORPUS}/${_name}.entrypoint.sh" ]] || {
    echo "fixture missing: ${_name}.entrypoint.sh" >&2
    return 1
  }
  mkdir -p "${_d}/script"
  cp -- "${CORPUS}/${_name}.Dockerfile" "${_d}/Dockerfile"
  cp -- "${CORPUS}/${_name}.entrypoint.sh" "${_d}/script/entrypoint.sh"
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
  cp -- "${_d}/script/entrypoint.sh" "${_d}/out.entrypoint"
}

# _check_case <case> -- regenerate and compare each output with its golden.
_check_case() {
  local _name="s43_sc1090_${1}" _d="${BATS_TEST_TMPDIR}/${1}" _e _bad=0
  for _e in dockerfile entrypoint files events; do
    [[ -f "${GOLDEN}/${_name}.${_e}" ]] || {
      echo "golden missing: ${_name}.${_e}" >&2
      _bad=1
    }
  done
  (( _bad == 0 )) || return 1
  _regen_case "$1" || return 1
  for _e in dockerfile entrypoint files events; do
    cmp -- "${_d}/out.${_e}" "${GOLDEN}/${_name}.${_e}" || _bad=1
  done
  (( _bad == 0 ))
}

# ── one test per case ───────────────────────────────────────────────────────

# why: a SC1091-only disable line is widened to SC1090,SC1091.
@test "s43 sc1090 golden: patch case is rewritten" {
  run _check_case patch
  assert_success
}

# why: an entrypoint already carrying SC1090,SC1091 is the fixed point.
@test "s43 sc1090 golden: done case is unchanged" {
  run _check_case done
  assert_success
}

# why: leading / inner / trailing whitespace of the directive line is preserved.
@test "s43 sc1090 golden: indent case keeps its whitespace" {
  run _check_case indent
  assert_success
}

# ── literal expectations, independent of the goldens ────────────────────────

# why: the issue gives the patch events as literals; pin them so a wrong
# golden cannot pass by being regenerated the same way.
@test "s43 sc1090 golden: patch events golden equals the issue's literal events" {
  run cat "${GOLDEN}/s43_sc1090_patch.events"
  assert_success
  assert_output "$(printf '%s\n%s' \
    $'entrypoint_patched\t  entrypoint patched: shellcheck SC1091 -> SC1090,SC1091 (#567 m6)' \
    $'dockerfile_migrations_reported\t  Dockerfile migrations: 1 of 16 matched (sc1090), 1 file(s) rewritten\tmatched=1\tavailable=16\tnames=sc1090\trewritten=1')"
}

# why: the issue gives the patched entrypoint as a literal.
@test "s43 sc1090 golden: patch entrypoint golden equals the issue's literal" {
  run cat "${GOLDEN}/s43_sc1090_patch.entrypoint"
  assert_success
  assert_output "$(printf '%s\n%s\n%s' \
    '#!/usr/bin/env bash' \
    '# shellcheck disable=SC1090,SC1091' \
    'source "/opt/ros/${ROS_DISTRO}/setup.bash"')"
}

# why: the patch input is the issue's literal three lines.
@test "s43 sc1090 golden: patch entrypoint fixture equals the issue's literal input" {
  run cat "${CORPUS}/s43_sc1090_patch.entrypoint.sh"
  assert_success
  assert_output "$(printf '%s\n%s\n%s' \
    '#!/usr/bin/env bash' \
    '# shellcheck disable=SC1091' \
    'source "/opt/ros/${ROS_DISTRO}/setup.bash"')"
}

# why: the issue gives the patch files output as the single path
# ./script/entrypoint.sh.
@test "s43 sc1090 golden: patch files golden is the single entrypoint path" {
  run cat "${GOLDEN}/s43_sc1090_patch.files"
  assert_output "./script/entrypoint.sh"
}

# why: the fixed point is a no-op: 0-byte .files, one report event.
@test "s43 sc1090 golden: done files golden is 0 bytes and events literal" {
  [[ -f "${GOLDEN}/s43_sc1090_done.files" ]]
  [[ ! -s "${GOLDEN}/s43_sc1090_done.files" ]]
  run cat "${GOLDEN}/s43_sc1090_done.events"
  assert_success
  assert_output $'dockerfile_migrations_reported\t  Dockerfile migrations: 0 of 16 matched (none), 0 file(s) rewritten\tmatched=0\tavailable=16\tnames=none\trewritten=0'
}

# why: nothing is rewritten, so the done entrypoint golden is the fixture bytes.
@test "s43 sc1090 golden: done entrypoint golden equals its fixture" {
  cmp -- "${CORPUS}/s43_sc1090_done.entrypoint.sh" "${GOLDEN}/s43_sc1090_done.entrypoint"
}

# why: the indent case has the same files / events as patch (issue item 3).
@test "s43 sc1090 golden: indent files and events goldens equal the patch ones" {
  local _e
  for _e in files events; do
    cmp -- "${GOLDEN}/s43_sc1090_indent.${_e}" "${GOLDEN}/s43_sc1090_patch.${_e}"
  done
}

# why: the issue gives the indent line with its exact spaces.
@test "s43 sc1090 golden: indent entrypoint golden line 2 keeps its spaces" {
  run sed -n '2p' "${GOLDEN}/s43_sc1090_indent.entrypoint"
  assert_output "  #  shellcheck disable=SC1090,SC1091  "
}

# why: every case's Dockerfile is the single line `FROM busybox AS devel`
# and migration 6 never touches it.
@test "s43 sc1090 golden: dockerfile fixtures and goldens are the one FROM line" {
  local _c
  for _c in patch done indent; do
    run cat "${CORPUS}/s43_sc1090_${_c}.Dockerfile"
    assert_output "FROM busybox AS devel"
    run cat "${GOLDEN}/s43_sc1090_${_c}.dockerfile"
    assert_output "FROM busybox AS devel"
  done
}

# ── the partition check ─────────────────────────────────────────────────────

# why: each sc1090 fixture has exactly its four goldens and no golden lacks a fixture.
@test "s43 sc1090 golden: every fixture has exactly its four goldens and no extra" {
  local _f _stem _e _bad=0
  for _f in "${CORPUS}"/s43_sc1090_*.Dockerfile; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .Dockerfile)"
    [[ -f "${CORPUS}/${_stem}.entrypoint.sh" ]] || {
      echo "fixture with no entrypoint: ${_stem}.entrypoint.sh" >&2
      _bad=1
    }
    for _e in dockerfile entrypoint files events; do
      if [[ ! -f "${GOLDEN}/${_stem}.${_e}" ]]; then
        echo "fixture with no golden: ${_stem}.${_e}" >&2
        _bad=1
      fi
    done
  done
  for _f in "${GOLDEN}"/s43_sc1090_*; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}")"
    _stem="${_stem%.*}"
    case "${_f##*.}" in
      dockerfile | entrypoint | files | events) ;;
      *) echo "unexpected golden extension: ${_f}" >&2; _bad=1 ;;
    esac
    if [[ ! -f "${CORPUS}/${_stem}.Dockerfile" ]]; then
      echo "golden with no fixture: ${_f}" >&2
      _bad=1
    fi
  done
  for _stem in patch done indent; do
    [[ -f "${CORPUS}/s43_sc1090_${_stem}.Dockerfile" ]] || {
      echo "fixture missing: s43_sc1090_${_stem}" >&2
      _bad=1
    }
  done
  (( _bad == 0 ))
}
