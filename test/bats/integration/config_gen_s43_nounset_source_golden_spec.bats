#!/usr/bin/env bats
#
# config_gen_s43_nounset_source_golden_spec.bats -- the s43 nounset_source
# (migration 8) corpus against the .dockerfile / .entrypoint / .files /
# .events goldens (base#2076, S43o of base#1776).
#
# why: Before any Go migration exists, the shell `apply_migrations`
# (dist/script/docker/lib/dockerfile_migrate.sh) is the oracle. The oracle is
# the shell after base#2153 (fix of base#2149): the `set +u` scope is tracked,
# comment-only lines are not wrapped. Every
# dockerfile/config-gen/testdata/corpus/s43/s43_nounset_<case>.Dockerfile has a
# sibling s43_nounset_<case>.entrypoint.sh input, and four goldens under
# testdata/golden/s43/:
#   .dockerfile  the Dockerfile bytes after apply_migrations
#   .entrypoint  the script/entrypoint.sh bytes after apply_migrations
#   .files       `migrated_files` stdout (0 bytes when nothing was rewritten)
#   .events      one projected event per line, tab separated:
#                <body> TAB <display> [TAB matched=.. TAB available=.. TAB
#                names=.. TAB rewritten=..]
# The inputs are copied to `Dockerfile` and `script/entrypoint.sh` in a scratch
# directory and run as relative paths (same approach as base#2057).

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

# _regen_case <case> -- run apply_migrations on s43_nounset_<case> and leave
# out.{dockerfile,entrypoint,files,events} in ${BATS_TEST_TMPDIR}/<case>/.
_regen_case() {
  local _name="s43_nounset_${1}" _d="${BATS_TEST_TMPDIR}/${1}"
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
  local _name="s43_nounset_${1}" _d="${BATS_TEST_TMPDIR}/${1}" _e _bad=0
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

# why: bare source gets set +u before the shellcheck directive and set -u after.
@test "s43 nounset golden: bare source is wrapped" {
  run _check_case bare
  assert_success
}

# why: an already guarded source is the fixed point, nothing is rewritten.
@test "s43 nounset golden: guarded source is unchanged" {
  run _check_case guarded
  assert_success
}

# why: only the unguarded second source is wrapped; the first group stays.
@test "s43 nounset golden: mixed wraps only the unguarded source" {
  run _check_case mixed
  assert_success
}

# why: with an orchestrator ENTRYPOINT and no set -u, the first line is wrapped.
@test "s43 nounset golden: orchestrator entrypoint source is wrapped" {
  run _check_case orch
  assert_success
}

# ── literal expectations, independent of the goldens ────────────────────────

# why: the issue gives the bare events as literals; pin them so a wrong golden
# cannot pass by being regenerated the same way.
@test "s43 nounset golden: bare events golden equals the issue's literal events" {
  run cat "${GOLDEN}/s43_nounset_bare.events"
  assert_success
  assert_output "$(printf '%s\n%s' \
    $'entrypoint_patched\t  entrypoint patched: nounset-guard ROS setup.bash source (#567 m8 / #579)' \
    $'dockerfile_migrations_reported\t  Dockerfile migrations: 1 of 16 matched (nounset_source), 1 file(s) rewritten\tmatched=1\tavailable=16\tnames=nounset_source\trewritten=1')"
}

# why: the issue gives the bare entrypoint result as a literal.
@test "s43 nounset golden: bare entrypoint golden equals the issue's literal" {
  run cat "${GOLDEN}/s43_nounset_bare.entrypoint"
  assert_success
  assert_output "$(printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'set +u' \
    '# shellcheck disable=SC1090,SC1091' \
    'source "/opt/ros/${ROS_DISTRO}/setup.bash"' \
    'set -u' \
    'exec "$@"')"
}

# why: the bare case records the rewritten script as ./script/entrypoint.sh.
@test "s43 nounset golden: bare files golden is ./script/entrypoint.sh" {
  run cat "${GOLDEN}/s43_nounset_bare.files"
  assert_output "./script/entrypoint.sh"
}

# why: the guarded fixed point: 0-byte .files, one report event, entrypoint == input.
@test "s43 nounset golden: guarded files golden is 0 bytes and events literal" {
  [[ -f "${GOLDEN}/s43_nounset_guarded.files" ]]
  [[ ! -s "${GOLDEN}/s43_nounset_guarded.files" ]]
  run cat "${GOLDEN}/s43_nounset_guarded.events"
  assert_success
  assert_output $'dockerfile_migrations_reported\t  Dockerfile migrations: 0 of 16 matched (none), 0 file(s) rewritten\tmatched=0\tavailable=16\tnames=none\trewritten=0'
}

# why: nothing is rewritten for guarded, so the entrypoint golden is the input bytes.
@test "s43 nounset golden: guarded entrypoint golden equals its input" {
  cmp -- "${CORPUS}/s43_nounset_guarded.entrypoint.sh" "${GOLDEN}/s43_nounset_guarded.entrypoint"
}

# why: mixed and orch end with the same event/files shape as bare.
@test "s43 nounset golden: mixed and orch events and files goldens equal bare's" {
  local _c _e
  for _c in mixed orch; do
    for _e in events files; do
      cmp -- "${GOLDEN}/s43_nounset_${_c}.${_e}" "${GOLDEN}/s43_nounset_bare.${_e}"
    done
  done
}

# why: this migration never changes the Dockerfile, so every .dockerfile golden
# is the fixture bytes.
@test "s43 nounset golden: every dockerfile golden equals its fixture" {
  local _c
  for _c in bare guarded mixed orch; do
    cmp -- "${CORPUS}/s43_nounset_${_c}.Dockerfile" "${GOLDEN}/s43_nounset_${_c}.dockerfile"
  done
}

# ── the partition check ─────────────────────────────────────────────────────

# why: each nounset fixture has exactly its four goldens and no golden lacks a fixture.
@test "s43 nounset golden: every fixture has exactly its four goldens and no extra" {
  local _f _stem _e _c _bad=0
  for _f in "${CORPUS}"/s43_nounset_*.Dockerfile; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .Dockerfile)"
    [[ -f "${CORPUS}/${_stem}.entrypoint.sh" ]] || {
      echo "fixture with no entrypoint input: ${_stem}" >&2
      _bad=1
    }
    for _e in dockerfile entrypoint files events; do
      if [[ ! -f "${GOLDEN}/${_stem}.${_e}" ]]; then
        echo "fixture with no golden: ${_stem}.${_e}" >&2
        _bad=1
      fi
    done
  done
  for _f in "${GOLDEN}"/s43_nounset_*; do
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
  for _c in bare guarded mixed orch; do
    [[ -f "${CORPUS}/s43_nounset_${_c}.Dockerfile" ]] || {
      echo "fixture missing: s43_nounset_${_c}" >&2
      _bad=1
    }
  done
  (( _bad == 0 ))
}
