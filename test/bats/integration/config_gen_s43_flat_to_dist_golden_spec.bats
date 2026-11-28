#!/usr/bin/env bats
#
# config_gen_s43_flat_to_dist_golden_spec.bats -- the s43 flat_to_dist
# migration corpus against the .dockerfile / .files / .events goldens
# (base#2067, S43i of base#1776).
#
# why: Before any Go migration exists, the shell `apply_migrations`
# (dist/script/docker/lib/dockerfile_migrate.sh) is the oracle. Every
# dockerfile/config-gen/testdata/corpus/s43/s43_flat_<case>.Dockerfile has
# three goldens under testdata/golden/s43/ (same shape as base#2057):
#   .dockerfile  the Dockerfile bytes after apply_migrations
#   .files       `migrated_files` stdout (0 bytes when nothing was rewritten)
#   .events      one projected event per line, tab separated:
#                <body> TAB <display> [TAB matched=.. TAB available=.. TAB
#                names=.. TAB rewritten=..]
# The fixture is run as the relative path `Dockerfile` in a scratch directory.
# The prefix is s43_flat_, not s43_migrate_ (that is the base#2055 partition).

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

# _regen_case <case> -- run apply_migrations on s43_flat_<case>.Dockerfile
# and leave out.{dockerfile,files,events} in ${BATS_TEST_TMPDIR}/<case>/.
_regen_case() {
  local _name="s43_flat_${1}" _d="${BATS_TEST_TMPDIR}/${1}"
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
  local _name="s43_flat_${1}" _d="${BATS_TEST_TMPDIR}/${1}" _e _bad=0
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

# why: the flat lint-stage lib/wrapper COPYs are rewritten to .base/dist/.
@test "s43 flat golden: lint lib/wrapper COPYs are rewritten" {
  run _check_case lint
  assert_success
}

# why: the flat config COPY is rewritten, flags and destination unchanged.
@test "s43 flat golden: config COPY is rewritten" {
  run _check_case config
  assert_success
}

# why: two stages are both rewritten and the blank line between them is kept.
@test "s43 flat golden: mixed two-stage Dockerfile is rewritten" {
  run _check_case mixed
  assert_success
}

# why: an already-dist layout is the fixed point, nothing is rewritten.
@test "s43 flat golden: dist layout is unchanged" {
  run _check_case dist
  assert_success
}

# ── literal expectations, independent of the goldens ────────────────────────

# why: the issue gives event A as literals; pin them so a wrong golden cannot
# pass by being regenerated the same way. Cases lint, config, mixed share it.
@test "s43 flat golden: lint, config and mixed events goldens equal the issue's event A" {
  local _c
  for _c in lint config mixed; do
    run cat "${GOLDEN}/s43_flat_${_c}.events"
    assert_success
    assert_output "$(printf '%s\n%s' \
      $'dockerfile_patched\t  Dockerfile patched: flat .base/{config,script} -> .base/dist/ (#915)' \
      $'dockerfile_migrations_reported\t  Dockerfile migrations: 1 of 16 matched (flat_to_dist), 1 file(s) rewritten\tmatched=1\tavailable=16\tnames=flat_to_dist\trewritten=1')"
  done
}

# why: the issue gives the lint Dockerfile result as a literal.
@test "s43 flat golden: lint dockerfile golden equals the issue's literal" {
  run cat "${GOLDEN}/s43_flat_lint.dockerfile"
  assert_success
  assert_output "$(printf '%s\n%s\n%s' \
    'FROM busybox AS lint' \
    'COPY .base/dist/script/docker/lib /lint/lib' \
    'COPY .base/dist/script/docker/wrapper /lint/wrapper')"
}

# why: only the source changes; --chown/--chmod flags and destination stay.
@test "s43 flat golden: config dockerfile golden equals the issue's literal" {
  run cat "${GOLDEN}/s43_flat_config.dockerfile"
  assert_success
  assert_output "$(printf '%s\n%s' \
    'FROM busybox AS devel' \
    'COPY --chown="${USER}":"${GROUP}" --chmod=0755 .base/dist/config "${CONFIG_DIR}"')"
}

# why: both stages are rewritten and the blank line separator survives.
@test "s43 flat golden: mixed dockerfile golden equals the issue's literal" {
  run cat "${GOLDEN}/s43_flat_mixed.dockerfile"
  assert_success
  assert_output "$(printf '%s\n%s\n%s\n%s\n%s' \
    'FROM busybox AS lint' \
    'COPY .base/dist/script/docker/lib /lint/lib' \
    '' \
    'FROM busybox AS devel' \
    'COPY --chmod=0755 .base/dist/config "${CONFIG_DIR}"')"
}

# why: a rewrite is recorded as the Dockerfile path, one line.
@test "s43 flat golden: rewritten cases' files goldens are the single path Dockerfile" {
  local _c
  for _c in lint config mixed; do
    run cat "${GOLDEN}/s43_flat_${_c}.files"
    assert_output "Dockerfile"
  done
}

# why: the fixed point is a no-op: 0-byte .files, one report event (event B).
@test "s43 flat golden: dist files golden is 0 bytes and events literal" {
  [[ -f "${GOLDEN}/s43_flat_dist.files" ]]
  [[ ! -s "${GOLDEN}/s43_flat_dist.files" ]]
  run cat "${GOLDEN}/s43_flat_dist.events"
  assert_success
  assert_output $'dockerfile_migrations_reported\t  Dockerfile migrations: 0 of 16 matched (none), 0 file(s) rewritten\tmatched=0\tavailable=16\tnames=none\trewritten=0'
}

# why: nothing is rewritten, so the dockerfile golden must be the fixture bytes.
@test "s43 flat golden: dist dockerfile golden equals its fixture" {
  [[ -f "${GOLDEN}/s43_flat_dist.dockerfile" ]]
  cmp -- "${CORPUS}/s43_flat_dist.Dockerfile" "${GOLDEN}/s43_flat_dist.dockerfile"
}

# ── the partition check ─────────────────────────────────────────────────────

# why: each flat fixture has exactly the three goldens and no golden lacks a fixture.
@test "s43 flat golden: every fixture has exactly its three goldens and no extra" {
  local _f _stem _e _bad=0
  for _f in "${CORPUS}"/s43_flat_*.Dockerfile; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .Dockerfile)"
    for _e in dockerfile files events; do
      if [[ ! -f "${GOLDEN}/${_stem}.${_e}" ]]; then
        echo "fixture with no golden: ${_stem}.${_e}" >&2
        _bad=1
      fi
    done
  done
  for _f in "${GOLDEN}"/s43_flat_*; do
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
  for _stem in lint config mixed dist; do
    [[ -f "${CORPUS}/s43_flat_${_stem}.Dockerfile" ]] || {
      echo "fixture missing: s43_flat_${_stem}" >&2
      _bad=1
    }
  done
  (( _bad == 0 ))
}
