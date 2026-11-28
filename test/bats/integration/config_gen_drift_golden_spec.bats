#!/usr/bin/env bats
#
# config_gen_drift_golden_spec.bats -- the s82 corpus of the shell
# _check_setup_drift against testdata/golden/s82 (base#2090, slice S82g of
# base#1818 / base#1754 under base#1395).
#
# why: Before any Go code replaces the drift parsing, today's shell
# behaviour is pinned as goldens. The shell function is the oracle: this
# spec re-runs it on every input in a scratch directory and fails on any
# byte difference from the stored golden. The golden format is the one of
# base#2064:
#
#   rc=<exit code>
#   mode=<octal mode of the target file after the call, or absent>
#   --- file
#   <exact bytes of the target file after the call>
#   --- stdout
#   <stdout of the call>
#   --- stderr
#   <one event per line: SEVERITY body key=value ...>
#
# The checked artifact is .env.generated, whose bytes are the input, so
# mode is always absent and the file section is empty. Event values are
# written as JSON strings, so a stored value holding a newline stays on one
# line. The current uid is written as <UID>, both in the corpus (the
# placeholder is replaced by the real uid before the call) and in the
# events. _compute_conf_hash, _compute_dockerfile_hash, detect_gui and
# detect_gpu are stubbed (HASHNOW, DFNOW, false, false).

bats_require_minimum_version 1.5.0

setup() {
  load "${BATS_TEST_DIRNAME}/../unit/test_helper"
  TESTDATA="/source/dockerfile/config-gen/testdata"
  S="${BATS_TEST_TMPDIR}"
}

# Golden names with no corpus input: the case calls the function on a
# directory holding no .env.generated.
_S82_DRIFT_INPUTLESS=(s82_drift_absent)

# _drift_violations -- print one line per drift corpus input with no golden
# and per drift golden with neither an input nor a listed inputless name.
_drift_violations() {
  local _f _stem _n _ok
  for _f in "${TESTDATA}"/corpus/s82/s82_drift_*.env; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .env)"
    [[ -f "${TESTDATA}/golden/s82/${_stem}.golden" ]] \
      || printf 'corpus input with no golden: %s\n' "${_stem}"
  done
  for _f in "${TESTDATA}"/golden/s82/s82_drift_*.golden; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .golden)"
    _ok=0
    [[ -f "${TESTDATA}/corpus/s82/${_stem}.env" ]] && _ok=1
    for _n in "${_S82_DRIFT_INPUTLESS[@]}"; do
      [[ "${_n}" == "${_stem}" ]] && _ok=1
    done
    (( _ok == 1 )) || printf 'golden with no corpus input: %s\n' "${_stem}"
  done
  return 0
}

# _project_events <raw-json-lines-file> -- one line per event:
# SEVERITY body display="..." [detail="..."], values as JSON strings.
_project_events() {
  jq -r '[.severity_text, .body,
      ("display=" + (.attributes.display | tojson))]
    + (if .attributes.detail != null
       then ["detail=" + (.attributes.detail | tojson)] else [] end)
    | join(" ")' "$1"
}

# _run_drift_case <name> <input|-> -- run _check_setup_drift on ${S}/w and
# write the actual golden to ${S}/actual/<name>.golden. <input> is a corpus
# file copied to ${S}/w/.env.generated with <UID> replaced by the current
# uid; `-` leaves the directory without one.
_run_drift_case() {
  local _name="${1}" _input="${2}" _rc=0 _uid
  _uid="$(id -u)"
  rm -rf -- "${S}/w"
  mkdir -p "${S}/w" "${S}/actual"
  if [[ "${_input}" != - ]]; then
    sed "s/<UID>/${_uid}/g" "${TESTDATA}/corpus/s82/${_input}" \
      > "${S}/w/.env.generated"
  fi
  (
    export LOG_FORMAT=json
    # shellcheck source=dist/script/docker/lib/_lib.sh
    source /source/dist/script/docker/lib/_lib.sh
    # shellcheck source=dist/script/docker/lib/drift.sh
    source /source/dist/script/docker/lib/drift.sh
    _compute_conf_hash() { local -n _o="${2}"; _o="HASHNOW"; }
    _compute_dockerfile_hash() { local -n _o="${2}"; _o="DFNOW"; }
    detect_gui() { local -n _o="${1}"; _o="false"; }
    detect_gpu() { local -n _o="${1}"; _o="false"; }
    _check_setup_drift "${S}/w"
  ) > "${S}/stdout" 2> "${S}/stderr.raw" || _rc=$?
  _project_events "${S}/stderr.raw" > "${S}/stderr"
  {
    printf 'rc=%d\nmode=absent\n--- file\n--- stdout\n' "${_rc}"
    cat -- "${S}/stdout"
    printf -- '--- stderr\n'
    sed "s|${_uid}|<UID>|g" "${S}/stderr"
  } > "${S}/actual/${_name}.golden"
}

# _assert_golden <name> -- the stored golden exists and equals the actual
# one byte for byte. cmp, never $(...), which drops trailing LFs.
_assert_golden() {
  local _gold="${TESTDATA}/golden/s82/${1}.golden"
  [[ -f "${_gold}" ]] || fail "no golden for ${1}: ${_gold}"
  cmp -- "${_gold}" "${S}/actual/${1}.golden" \
    || fail "$(diff -u "${_gold}" "${S}/actual/${1}.golden")"
}

# why: a drift corpus input with no golden would be read against nothing,
# and a stale golden would stand for a case no longer run.
@test "s82 drift corpus: every input has a golden and every golden an input" {
  run _drift_violations
  assert_success
  assert_output ""
}

# why: with no .env.generated there is nothing to compare, so rc 0 and no
# event.
@test "s82 drift: an absent .env.generated reports nothing" {
  _run_drift_case s82_drift_absent -
  _assert_golden s82_drift_absent
}

# why: a file with no SETUP_* key stores nothing to compare, so every
# comparison is skipped: rc 0 and no event.
@test "s82 drift: a file with no SETUP_ key reports nothing" {
  _run_drift_case s82_drift_nokeys s82_drift_nokeys.env
  _assert_golden s82_drift_nokeys
}

# why: stored values equal to the current ones are in sync: rc 0, no event.
@test "s82 drift: stored values equal to the current ones report nothing" {
  _run_drift_case s82_drift_insync s82_drift_insync.env
  _assert_golden s82_drift_insync
}

# why: five stored values all differing from the current ones give rc 1,
# one env_drift_detected event, then one env_drift_detail per value in
# the order conf, Dockerfile, GPU, GUI, uid.
@test "s82 drift: five differing values give five detail events" {
  _run_drift_case s82_drift_all s82_drift_all.env
  _assert_golden s82_drift_all
}

# why: the expected events as literals from the issue, so a wrong golden
# cannot pass by being regenerated the same way as the shell wrote it.
@test "s82 drift: the five-difference golden equals the issue's literal events" {
  run cat "${TESTDATA}/golden/s82/s82_drift_all.golden"
  assert_success
  assert_output "$(printf '%s\n' \
    'rc=1' 'mode=absent' '--- file' '--- stdout' '--- stderr' \
    'WARN env_drift_detected display="drift detected since last setup.sh run:"' \
    'WARN env_drift_detail display="  - setup.toml modified since last setup" detail="setup.toml modified since last setup"' \
    'WARN env_drift_detail display="  - Dockerfile stage list changed since last setup (added/removed FROM ... AS <stage>)" detail="Dockerfile stage list changed since last setup (added/removed FROM ... AS <stage>)"' \
    'WARN env_drift_detail display="  - GPU detection changed: true → false" detail="GPU detection changed: true → false"' \
    'WARN env_drift_detail display="  - GUI detection changed: true → false" detail="GUI detection changed: true → false"' \
    'WARN env_drift_detail display="  - USER_UID changed: 99999 → <UID>" detail="USER_UID changed: 99999 → <UID>"')"
}

# why: SETUP_CONF_HASH twice with the same value is read as the two-line
# string HASHNOW LF HASHNOW, which differs from the current HASHNOW, so it
# is reported as drift.
@test "s82 drift: a duplicated SETUP_CONF_HASH is reported as drift" {
  _run_drift_case s82_drift_dup_hash s82_drift_dup_hash.env
  _assert_golden s82_drift_dup_hash
}

# why: GPU_ENABLED=false then GPU_ENABLED=true is read as the two-line
# value false LF true, kept with its embedded newline in the one detail.
@test "s82 drift: a repeated GPU_ENABLED keeps its embedded newline" {
  _run_drift_case s82_drift_dup_gpu s82_drift_dup_gpu.env
  _assert_golden s82_drift_dup_gpu
}

# ---------------------------------------------------------------------
# _announce_template_default_fallback (base#2091, slice S82h)
#
# The corpus input is the per-repo setup.toml, copied to ${S}/w/setup.toml;
# `-` leaves the directory without one. The golden format is the one above
# (mode=absent, empty file section); the events are WARN lines on stderr,
# run with the English messages (_LANG unset) and the real _setup_msg.
# ---------------------------------------------------------------------

_S82_FALLBACK_INPUTLESS=(s82_fallback_absent)

# _fallback_violations -- as _drift_violations, for s82_fallback_*.toml.
_fallback_violations() {
  local _f _stem _n _ok
  for _f in "${TESTDATA}"/corpus/s82/s82_fallback_*.toml; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .toml)"
    [[ -f "${TESTDATA}/golden/s82/${_stem}.golden" ]] \
      || printf 'corpus input with no golden: %s\n' "${_stem}"
  done
  for _f in "${TESTDATA}"/golden/s82/s82_fallback_*.golden; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .golden)"
    _ok=0
    [[ -f "${TESTDATA}/corpus/s82/${_stem}.toml" ]] && _ok=1
    for _n in "${_S82_FALLBACK_INPUTLESS[@]}"; do
      [[ "${_n}" == "${_stem}" ]] && _ok=1
    done
    (( _ok == 1 )) || printf 'golden with no corpus input: %s\n' "${_stem}"
  done
  return 0
}

# _run_fallback_case <name> <input|-> -- run _announce_template_default_fallback
# on ${S}/w and write the actual golden to ${S}/actual/<name>.golden.
_run_fallback_case() {
  local _name="${1}" _input="${2}" _rc=0
  rm -rf -- "${S}/w"
  mkdir -p "${S}/w" "${S}/actual"
  if [[ "${_input}" != - ]]; then
    cp -- "${TESTDATA}/corpus/s82/${_input}" "${S}/w/setup.toml"
  fi
  (
    export LOG_FORMAT=json
    unset _LANG
    # shellcheck source=dist/script/docker/lib/_lib.sh
    source /source/dist/script/docker/lib/_lib.sh
    # shellcheck source=dist/script/docker/wrapper/setup.sh
    source /source/dist/script/docker/wrapper/setup.sh
    # shellcheck source=dist/script/docker/lib/drift.sh
    source /source/dist/script/docker/lib/drift.sh
    _announce_template_default_fallback "${S}/w"
  ) > "${S}/stdout" 2> "${S}/stderr.raw" || _rc=$?
  _project_events "${S}/stderr.raw" > "${S}/stderr"
  {
    printf 'rc=%d\nmode=absent\n--- file\n--- stdout\n' "${_rc}"
    cat -- "${S}/stdout"
    printf -- '--- stderr\n'
    cat -- "${S}/stderr"
  } > "${S}/actual/${_name}.golden"
}

# why: a fallback corpus input with no golden would be read against
# nothing, and a stale golden would stand for a case no longer run.
@test "s82 fallback corpus: every input has a golden and every golden an input" {
  run _fallback_violations
  assert_success
  assert_output ""
}

# why: with no setup.toml the notice is conf_no_repo_conf, rc 0, nothing
# on stdout.
@test "s82 fallback: an absent setup.toml gives conf_no_repo_conf" {
  _run_fallback_case s82_fallback_absent -
  _assert_golden s82_fallback_absent
}

# why: a setup.toml with no [section] header gives conf_empty_repo_conf.
@test "s82 fallback: a setup.toml without a header gives conf_empty_repo_conf" {
  _run_fallback_case s82_fallback_nosection s82_fallback_nosection.toml
  _assert_golden s82_fallback_nosection
}

# why: an indented [x] counts as a header, so no event.
@test "s82 fallback: an indented header reports nothing" {
  _run_fallback_case s82_fallback_indented s82_fallback_indented.toml
  _assert_golden s82_fallback_indented
}

# why: an empty setup.toml has no header, so conf_empty_repo_conf.
@test "s82 fallback: an empty setup.toml gives conf_empty_repo_conf" {
  _run_fallback_case s82_fallback_empty s82_fallback_empty.toml
  _assert_golden s82_fallback_empty
}

# why: the expected events as literals from the issue, so a wrong golden
# cannot pass by being regenerated the same way as the shell wrote it.
@test "s82 fallback: the goldens equal the issue's literal events" {
  run cat "${TESTDATA}/golden/s82/s82_fallback_absent.golden"
  assert_success
  assert_output "$(printf '%s\n' \
    'rc=0' 'mode=absent' '--- file' '--- stdout' '--- stderr' \
    'WARN conf_no_repo_conf display="no per-repo setup.toml — using template defaults for all sections"')"
  run cat "${TESTDATA}/golden/s82/s82_fallback_nosection.golden"
  assert_success
  assert_output "$(printf '%s\n' \
    'rc=0' 'mode=absent' '--- file' '--- stdout' '--- stderr' \
    'WARN conf_empty_repo_conf display="per-repo setup.toml has no section overrides — using template defaults for all sections"')"
  run cat "${TESTDATA}/golden/s82/s82_fallback_indented.golden"
  assert_success
  assert_output "$(printf '%s\n' \
    'rc=0' 'mode=absent' '--- file' '--- stdout' '--- stderr')"
}
