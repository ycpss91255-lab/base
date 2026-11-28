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

# _pairing_violations <glob-prefix> <input-ext> <inputless-name>... -- print
# one line per corpus input s82_<prefix>*.<ext> with no golden and per golden
# with neither an input nor a listed inputless name.
_pairing_violations() {
  local _prefix="${1}" _ext="${2}" _f _stem _n _ok
  shift 2
  for _f in "${TESTDATA}"/corpus/s82/"${_prefix}"*."${_ext}"; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" ."${_ext}")"
    [[ -f "${TESTDATA}/golden/s82/${_stem}.golden" ]] \
      || printf 'corpus input with no golden: %s\n' "${_stem}"
  done
  for _f in "${TESTDATA}"/golden/s82/"${_prefix}"*.golden; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .golden)"
    _ok=0
    [[ -f "${TESTDATA}/corpus/s82/${_stem}.${_ext}" ]] && _ok=1
    for _n in "$@"; do
      [[ "${_n}" == "${_stem}" ]] && _ok=1
    done
    (( _ok == 1 )) || printf 'golden with no corpus input: %s\n' "${_stem}"
  done
  return 0
}

# _drift_violations -- _pairing_violations for the s82_drift_*.env corpus.
_drift_violations() {
  _pairing_violations s82_drift_ env "${_S82_DRIFT_INPUTLESS[@]}"
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

# _fallback_violations -- _pairing_violations for the s82_fallback_*.toml
# corpus.
_fallback_violations() {
  _pairing_violations s82_fallback_ toml "${_S82_FALLBACK_INPUTLESS[@]}"
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

# ---------------------------------------------------------------------
# _compute_conf_hash (base#2092, slice S82i)
#
# The corpus inputs are the layers: s82_hash_<case>.toml is copied to
# ${S}/w/setup.toml and s82_hash_<case>.local, when present, to
# ${S}/w/setup.local.toml. `-` leaves the layer absent. _SETUP_SCRIPT_DIR
# is unset, so the chain is <dir>/setup.toml then <dir>/setup.local.toml
# (no template layer). The digest is printed on stdout as `<digest>` LF.
# The golden format is the one above (mode=absent, empty file section).
# ---------------------------------------------------------------------

_S82_HASH_INPUTLESS=(s82_hash_absent s82_hash_refused)

# _hash_violations -- _pairing_violations for the s82_hash_*.toml corpus.
_hash_violations() {
  _pairing_violations s82_hash_ toml "${_S82_HASH_INPUTLESS[@]}"
}

# _run_hash_case <name> <setup.toml input|-> <setup.local.toml input|-> [local-override]
# -- run _compute_conf_hash on ${S}/w and write the actual golden to
# ${S}/actual/<name>.golden. A fourth argument sets _SETUP_CONF_LOCAL to
# that path (relative to ${S}/w), the way a caller addresses a layer.
_run_hash_case() {
  local _name="${1}" _toml="${2}" _local="${3}" _over="${4:-}" _rc=0
  rm -rf -- "${S}/w"
  mkdir -p "${S}/w" "${S}/actual"
  if [[ "${_toml}" != - ]]; then
    cp -- "${TESTDATA}/corpus/s82/${_toml}" "${S}/w/setup.toml"
  fi
  if [[ "${_local}" != - ]]; then
    cp -- "${TESTDATA}/corpus/s82/${_local}" "${S}/w/setup.local.toml"
  fi
  (
    export LOG_FORMAT=json
    unset _SETUP_SCRIPT_DIR _SETUP_CONF_LOCAL
    [[ -z "${_over}" ]] || export _SETUP_CONF_LOCAL="${S}/w/${_over}"
    # shellcheck source=dist/script/docker/lib/_lib.sh
    source /source/dist/script/docker/lib/_lib.sh
    # shellcheck source=dist/script/docker/lib/resolve.sh
    source /source/dist/script/docker/lib/resolve.sh
    local _out=""
    _compute_conf_hash "${S}/w" _out || exit 1
    printf '%s\n' "${_out}"
  ) > "${S}/stdout" 2> "${S}/stderr.raw" || _rc=$?
  _project_events "${S}/stderr.raw" > "${S}/stderr"
  {
    printf 'rc=%d\nmode=absent\n--- file\n--- stdout\n' "${_rc}"
    cat -- "${S}/stdout"
    printf -- '--- stderr\n'
    sed "s|${S}|<S>|g" "${S}/stderr"
  } > "${S}/actual/${_name}.golden"
}

# _golden_digest <name> -- the digest line of a stored golden (line 5).
_golden_digest() {
  sed -n '5p' "${TESTDATA}/golden/s82/${1}.golden"
}

# _sha_of <printf-format>... -- sha256 of the literal bytes, from sha256sum
# over printf, never from the function under test.
_sha_of() {
  # shellcheck disable=SC2059
  printf "$@" | sha256sum | cut -d' ' -f1
}

# why: a hash corpus input with no golden would be read against nothing,
# and a stale golden would stand for a case no longer run.
@test "s82 hash corpus: every input has a golden and every golden an input" {
  run _hash_violations
  assert_success
  assert_output ""
}

# why: with neither layer present the hash is that of empty input.
@test "s82 hash: no layer present gives the sha256 of empty input" {
  _run_hash_case s82_hash_absent - -
  _assert_golden s82_hash_absent
}

# why: a lone setup.toml is hashed on its own bytes.
@test "s82 hash: a lone setup.toml is hashed on its own bytes" {
  _run_hash_case s82_hash_base s82_hash_base.toml -
  _assert_golden s82_hash_base
}

# why: both layers are hashed as setup.toml bytes then setup.local.toml
# bytes, with no separator.
@test "s82 hash: both layers are concatenated without a separator" {
  _run_hash_case s82_hash_both s82_hash_both.toml s82_hash_both.local
  _assert_golden s82_hash_both
}

# why: swapping the two layers' contents changes the digest, so the order
# matters.
@test "s82 hash: swapping the layer contents changes the hash" {
  _run_hash_case s82_hash_swapped s82_hash_swapped.toml s82_hash_swapped.local
  _assert_golden s82_hash_swapped
}

# why: one changed byte in setup.toml changes the digest.
@test "s82 hash: one changed byte in setup.toml changes the hash" {
  _run_hash_case s82_hash_changed s82_hash_changed.toml -
  _assert_golden s82_hash_changed
}

# why: one changed byte in setup.local.toml changes the digest.
@test "s82 hash: one changed byte in setup.local.toml changes the hash" {
  _run_hash_case s82_hash_localchanged s82_hash_localchanged.toml s82_hash_localchanged.local
  _assert_golden s82_hash_localchanged
}

# why: a refused chain (the addressed override cannot be read) gives rc 1
# and no digest.
@test "s82 hash: a refused layer chain gives rc 1 and no digest" {
  _run_hash_case s82_hash_refused - - missing.toml
  _assert_golden s82_hash_refused
}

# why: the expected digests as literals computed by sha256sum over
# printf-built bytes, so a wrong golden cannot pass by being regenerated
# the same way as the shell wrote it.
@test "s82 hash: the goldens equal the sha256 of the issue's literal bytes" {
  run _golden_digest s82_hash_absent
  assert_output "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  run _golden_digest s82_hash_base
  assert_output "$(_sha_of '[a]\nx = 1\n')"
  run _golden_digest s82_hash_both
  assert_output "$(_sha_of '[a]\nx = 1\n[b]\ny = 2\n')"
  run _golden_digest s82_hash_swapped
  assert_output "$(_sha_of '[b]\ny = 2\n[a]\nx = 1\n')"
  run _golden_digest s82_hash_changed
  assert_output "$(_sha_of '[a]\nx = 2\n')"
  run _golden_digest s82_hash_localchanged
  assert_output "$(_sha_of '[a]\nx = 1\n[b]\ny = 3\n')"
  run cat "${TESTDATA}/golden/s82/s82_hash_refused.golden"
  assert_success
  assert_line --index 0 'rc=1'
  assert_line --index 4 '--- stderr'
}
