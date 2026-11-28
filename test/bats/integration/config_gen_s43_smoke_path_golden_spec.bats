#!/usr/bin/env bats
#
# config_gen_s43_smoke_path_golden_spec.bats -- the s43 smoke_copy path
# boundary and continued whole-directory COPY corpus against the .dockerfile /
# .files / .events goldens (base#2345, S43g2 of base#2063 / base#1776).
#
# why: Before any Go migration exists, the shell `apply_migrations`
# (dist/script/docker/lib/dockerfile_migrate.sh) is the oracle. Every
# dockerfile/config-gen/testdata/corpus/s43/s43_scpath_<case>.Dockerfile has
# a `.tree` next to it and three goldens under testdata/golden/s43/:
#   .tree        one path per line, relative to .base/dist/test/bats/smoke/;
#                a trailing `/` is an empty directory, otherwise a 0-byte
#                file; a 0-byte .tree creates nothing
#   .dockerfile  the Dockerfile bytes after apply_migrations
#   .files       `migrated_files` stdout (0 bytes when nothing was rewritten)
#   .events      one projected event per line, tab separated:
#                <body> TAB <display> [TAB matched=.. TAB available=.. TAB
#                names=.. TAB rewritten=..]
# The fixture is run as the relative path `Dockerfile` in a scratch directory.
# apply_migrations writes its warn events to stderr, so the events are merged
# with 2>&1 to keep the order in which they were emitted.

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

# _build_tree <tree-file> <smoke-root> -- create the smoke tree the .tree
# file describes.
_build_tree() {
  local _line
  mkdir -p -- "$2"
  while IFS= read -r _line || [[ -n "${_line}" ]]; do
    [[ -n "${_line}" ]] || continue
    if [[ "${_line}" == */ ]]; then
      mkdir -p -- "$2/${_line}"
    else
      mkdir -p -- "$2/$(dirname -- "${_line}")"
      : > "$2/${_line}"
    fi
  done < "$1"
}

# _regen_case <case> -- run apply_migrations on s43_scpath_<case>.Dockerfile
# against its .tree and leave out.{dockerfile,files,events} in
# ${BATS_TEST_TMPDIR}/<case>/.
_regen_case() {
  local _name="s43_scpath_${1}" _d="${BATS_TEST_TMPDIR}/${1}" _e
  for _e in Dockerfile tree; do
    [[ -f "${CORPUS}/${_name}.${_e}" ]] || {
      echo "fixture missing: ${_name}.${_e}" >&2
      return 1
    }
  done
  mkdir -p "${_d}"
  cp -- "${CORPUS}/${_name}.Dockerfile" "${_d}/Dockerfile"
  _build_tree "${CORPUS}/${_name}.tree" "${_d}/.base/dist/test/bats/smoke"
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
  local _name="s43_scpath_${1}" _d="${BATS_TEST_TMPDIR}/${1}" _e _bad=0
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

# why: `xbase/test/smoke` looks like the retired tree but is not
# `.base/test/smoke`; only the real `.base/test/smoke/` line is rewritten.
@test "s43 scpath golden: lookalike xbase path is left alone, only the real one is rewritten" {
  run _check_case xbase
  assert_success
}

# why: `.base/test/smoke_helpers` only starts with smoke; detect stops at the
# path boundary and the Dockerfile is byte-identical.
@test "s43 scpath golden: smoke_helpers sibling path is not detected" {
  run _check_case sibling
  assert_success
}

# why: a whole-directory COPY written with a line continuation is copied twice
# as a whole two-physical-line group, once for shared and once for the stage.
@test "s43 scpath golden: continued whole-directory COPY is duplicated as a group" {
  run _check_case contwhole
  assert_success
}

# ── literal expectations, independent of the goldens ────────────────────────

# why: the issue gives the xbase result as a literal; pin it so a wrong golden
# cannot pass by being regenerated the same way.
@test "s43 scpath golden: xbase dockerfile golden equals the issue's literal" {
  run cat "${GOLDEN}/s43_scpath_xbase.dockerfile"
  assert_success
  assert_output "$(printf '%s\n%s\n%s' \
    'FROM devel AS custom-test' \
    'COPY xbase/test/smoke/ /smoke_test/' \
    'COPY .base/dist/test/bats/smoke/shared/ /smoke_test/')"
}

# why: the issue gives the xbase events as literals, in emitted order.
@test "s43 scpath golden: xbase events golden equals the issue's literal events" {
  run cat "${GOLDEN}/s43_scpath_xbase.events"
  assert_success
  assert_output "$(printf '%s\n%s' \
    $'dockerfile_patched\t  Dockerfile patched: .base/test/smoke/ -> per-stage smoke COPYs under .base/dist/test/bats/smoke/ (#928)' \
    $'dockerfile_migrations_reported\t  Dockerfile migrations: 1 of 16 matched (smoke_copy), 1 file(s) rewritten\tmatched=1\tavailable=16\tnames=smoke_copy\trewritten=1')"
}

# why: a rewrite is recorded as the Dockerfile path, one line.
@test "s43 scpath golden: xbase files golden is the single path Dockerfile" {
  run cat "${GOLDEN}/s43_scpath_xbase.files"
  assert_output "Dockerfile"
}

# why: nothing is rewritten for the sibling path: 0-byte .files and the single
# report event, per the issue.
@test "s43 scpath golden: sibling files golden is 0 bytes and events literal" {
  [[ -f "${GOLDEN}/s43_scpath_sibling.files" ]]
  [[ ! -s "${GOLDEN}/s43_scpath_sibling.files" ]]
  run cat "${GOLDEN}/s43_scpath_sibling.events"
  assert_success
  assert_output $'dockerfile_migrations_reported\t  Dockerfile migrations: 0 of 16 matched (none), 0 file(s) rewritten\tmatched=0\tavailable=16\tnames=none\trewritten=0'
}

# why: nothing is rewritten, so the dockerfile golden must be the fixture bytes.
@test "s43 scpath golden: sibling dockerfile golden equals its fixture" {
  cmp -- "${CORPUS}/s43_scpath_sibling.Dockerfile" "${GOLDEN}/s43_scpath_sibling.dockerfile"
}

# why: the issue gives the contwhole result as a literal, the two physical
# lines copied as one group for shared then devel-test.
@test "s43 scpath golden: contwhole dockerfile golden equals the issue's literal" {
  run cat "${GOLDEN}/s43_scpath_contwhole.dockerfile"
  assert_success
  assert_output "$(printf '%s\n%s\n%s\n%s\n%s' \
    'FROM devel AS devel-test' \
    'COPY .base/dist/test/bats/smoke/shared/ \' \
    '     /smoke_test/' \
    'COPY .base/dist/test/bats/smoke/devel-test/ \' \
    '     /smoke_test/')"
}

# why: the issue says the contwhole events equal the xbase events.
@test "s43 scpath golden: contwhole events golden equals the xbase events golden" {
  cmp -- "${GOLDEN}/s43_scpath_contwhole.events" "${GOLDEN}/s43_scpath_xbase.events"
}

# why: a rewrite is recorded as the Dockerfile path, one line.
@test "s43 scpath golden: contwhole files golden is the single path Dockerfile" {
  run cat "${GOLDEN}/s43_scpath_contwhole.files"
  assert_output "Dockerfile"
}

# ── the partition check ─────────────────────────────────────────────────────

# why: each scpath fixture has exactly one .tree and the three goldens, and
# no golden or tree lacks a fixture.
@test "s43 scpath golden: every fixture has its tree and three goldens and no extra" {
  local _f _stem _e _bad=0
  for _f in "${CORPUS}"/s43_scpath_*.Dockerfile; do
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
  for _f in "${CORPUS}"/s43_scpath_*.tree; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .tree)"
    if [[ ! -f "${CORPUS}/${_stem}.Dockerfile" ]]; then
      echo "tree with no fixture: ${_f}" >&2
      _bad=1
    fi
  done
  for _f in "${GOLDEN}"/s43_scpath_*; do
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
  for _stem in xbase sibling contwhole; do
    [[ -f "${CORPUS}/s43_scpath_${_stem}.Dockerfile" ]] || {
      echo "fixture missing: s43_scpath_${_stem}" >&2
      _bad=1
    }
  done
  (( _bad == 0 ))
}
