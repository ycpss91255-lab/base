#!/usr/bin/env bats
#
# config_gen_s43_pip_helper_golden_spec.bats -- the s43 pip_helper
# (migration 2) corpus against the .dockerfile / .files / .events goldens
# (base#2330, S43d1 of base#2059).
#
# why: Before any Go migration exists, the shell `apply_migrations`
# (dist/script/docker/lib/dockerfile_migrate.sh) is the oracle. Every
# dockerfile/config-gen/testdata/corpus/s43/s43_pip_<case>.Dockerfile has
# three goldens under testdata/golden/s43/ (same shape as base#2057):
#   .dockerfile  the Dockerfile bytes after apply_migrations
#   .files       `migrated_files` stdout (0 bytes when nothing was rewritten)
#   .events      one projected event per line, tab separated:
#                <body> TAB <display> [TAB matched=.. TAB available=.. TAB
#                names=.. TAB rewritten=..]
# Two differences from base#2057:
#   - sidecar: the scratch directory always gets config/; an optional
#     s43_pip_<case>.requirements is copied to config/pip/requirements.txt.
#   - events: dockerfile_patched / dockerfile_unchanged are _log_warn lines on
#     stderr, only the report is on stdout, so stdout and stderr are merged
#     (2>&1) and the emit order is the event order.
# The fixture is run as the relative path `Dockerfile` in a scratch directory.
# The prefix is s43_pip_, not s43_migrate_ (that is the base#2055 partition).

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

# _regen_case <case> -- run apply_migrations on s43_pip_<case>.Dockerfile
# (with its optional .requirements sidecar) and leave
# out.{dockerfile,files,events} in ${BATS_TEST_TMPDIR}/<case>/.
_regen_case() {
  local _name="s43_pip_${1}" _d="${BATS_TEST_TMPDIR}/${1}"
  [[ -f "${CORPUS}/${_name}.Dockerfile" ]] || {
    echo "fixture missing: ${_name}.Dockerfile" >&2
    return 1
  }
  mkdir -p "${_d}/config"
  cp -- "${CORPUS}/${_name}.Dockerfile" "${_d}/Dockerfile"
  if [[ -f "${CORPUS}/${_name}.requirements" ]]; then
    mkdir -p "${_d}/config/pip"
    cp -- "${CORPUS}/${_name}.requirements" "${_d}/config/pip/requirements.txt"
  fi
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
  local _name="s43_pip_${1}" _d="${BATS_TEST_TMPDIR}/${1}" _e _bad=0
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

# why: no requirements file, so the pip block (comment + RUN) is dropped.
@test "s43 pip golden: absent requirements drops the pip block" {
  run _check_case absent
  assert_success
}

# why: a comment-only requirements file counts as a placeholder, so the block is dropped.
@test "s43 pip golden: placeholder requirements drops the pip block" {
  run _check_case placeholder
  assert_success
}

# why: a real requirement keeps the pip line, nothing is rewritten.
@test "s43 pip golden: real requirements keeps the pip line" {
  run _check_case real
  assert_success
}

# why: a Dockerfile with no pip line matches nothing.
@test "s43 pip golden: no pip line matches nothing" {
  run _check_case noline
  assert_success
}

# ── literal expectations, independent of the goldens ────────────────────────

# why: the issue gives the dropped-block events as literals; pin them so a
# wrong golden cannot pass by being regenerated the same way.
@test "s43 pip golden: absent events golden equals the issue's literal events" {
  run cat "${GOLDEN}/s43_pip_absent.events"
  assert_success
  assert_output "$(printf '%s\n%s' \
    $'dockerfile_patched\t  Dockerfile patched: dropped retired CONFIG_DIR pip helper line (#567 m2) — re-add an explicit pip step if you ship a real requirements file' \
    $'dockerfile_migrations_reported\t  Dockerfile migrations: 1 of 16 matched (pip_helper), 1 file(s) rewritten\tmatched=1\tavailable=16\tnames=pip_helper\trewritten=1')"
}

# why: the issue gives the Dockerfile after the drop as a literal.
@test "s43 pip golden: absent dockerfile golden equals the issue's literal" {
  run cat "${GOLDEN}/s43_pip_absent.dockerfile"
  assert_success
  assert_output "$(printf '%s\n%s' 'FROM busybox AS sys' 'RUN echo done')"
}

# why: a rewrite is recorded as the Dockerfile path, one line.
@test "s43 pip golden: absent files golden is the single path Dockerfile" {
  run cat "${GOLDEN}/s43_pip_absent.files"
  assert_output "Dockerfile"
}

# why: the comment-only requirements ends in the same state as the absent one.
@test "s43 pip golden: placeholder goldens are byte-identical to absent goldens" {
  local _e
  for _e in dockerfile files events; do
    cmp -- "${GOLDEN}/s43_pip_placeholder.${_e}" "${GOLDEN}/s43_pip_absent.${_e}"
  done
}

# why: real requirements are an unchanged warn plus a 0-rewritten report, the issue gives them as literals.
@test "s43 pip golden: real events golden equals the issue's literal events" {
  run cat "${GOLDEN}/s43_pip_real.events"
  assert_success
  assert_output "$(printf '%s\n%s' \
    $'dockerfile_unchanged\t  Dockerfile unchanged: retired CONFIG_DIR pip helper line kept — config/pip/requirements.txt carries real requirements, so the line still installs them (#567 m2)' \
    $'dockerfile_migrations_reported\t  Dockerfile migrations: 1 of 16 matched (pip_helper), 0 file(s) rewritten\tmatched=1\tavailable=16\tnames=pip_helper\trewritten=0')"
}

# why: nothing is rewritten, so .files is 0 bytes and the dockerfile golden is the fixture bytes.
@test "s43 pip golden: real files golden is 0 bytes and dockerfile equals its fixture" {
  [[ -f "${GOLDEN}/s43_pip_real.files" ]]
  [[ ! -s "${GOLDEN}/s43_pip_real.files" ]]
  cmp -- "${CORPUS}/s43_pip_real.Dockerfile" "${GOLDEN}/s43_pip_real.dockerfile"
}

# why: no pip line is a no-op: one report event with names=none.
@test "s43 pip golden: noline events golden is the single none report" {
  run cat "${GOLDEN}/s43_pip_noline.events"
  assert_success
  assert_output $'dockerfile_migrations_reported\t  Dockerfile migrations: 0 of 16 matched (none), 0 file(s) rewritten\tmatched=0\tavailable=16\tnames=none\trewritten=0'
}

# why: nothing is rewritten, so .files is 0 bytes and the dockerfile golden is the fixture bytes.
@test "s43 pip golden: noline files golden is 0 bytes and dockerfile equals its fixture" {
  [[ -f "${GOLDEN}/s43_pip_noline.files" ]]
  [[ ! -s "${GOLDEN}/s43_pip_noline.files" ]]
  cmp -- "${CORPUS}/s43_pip_noline.Dockerfile" "${GOLDEN}/s43_pip_noline.dockerfile"
}

# ── the partition check ─────────────────────────────────────────────────────

# why: each pip fixture has exactly the three goldens, no golden or sidecar
# lacks a fixture. Driven by the fixture list so later fixtures do not break it.
@test "s43 pip golden: every fixture has exactly its three goldens and no extra" {
  local _f _stem _e _bad=0
  for _f in "${CORPUS}"/s43_pip_*.Dockerfile; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .Dockerfile)"
    for _e in dockerfile files events; do
      if [[ ! -f "${GOLDEN}/${_stem}.${_e}" ]]; then
        echo "fixture with no golden: ${_stem}.${_e}" >&2
        _bad=1
      fi
    done
  done
  for _f in "${GOLDEN}"/s43_pip_*; do
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
  for _f in "${CORPUS}"/s43_pip_*.requirements; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .requirements)"
    if [[ ! -f "${CORPUS}/${_stem}.Dockerfile" ]]; then
      echo "sidecar with no fixture: ${_f}" >&2
      _bad=1
    fi
  done
  for _stem in absent placeholder real noline; do
    [[ -f "${CORPUS}/s43_pip_${_stem}.Dockerfile" ]] || {
      echo "fixture missing: s43_pip_${_stem}" >&2
      _bad=1
    }
  done
  (( _bad == 0 ))
}
