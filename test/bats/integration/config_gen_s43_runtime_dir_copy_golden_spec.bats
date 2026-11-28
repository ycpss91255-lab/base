#!/usr/bin/env bats
#
# config_gen_s43_runtime_dir_copy_golden_spec.bats -- the s43 runtime_dir_copy
# (per-file helper COPYs -> one dir COPY) corpus against the .dockerfile / .files / .events goldens
# (base#2070, S43k of base#1776).
#
# why: Before any Go migration exists, the shell `apply_migrations`
# (dist/script/docker/lib/dockerfile_migrate.sh) is the oracle. Every
# dockerfile/config-gen/testdata/corpus/s43/s43_rdcopy_<case>.Dockerfile has
# three goldens under testdata/golden/s43/ (same shape as base#2055):
#   .dockerfile  the Dockerfile bytes after apply_migrations
#   .files       `migrated_files` stdout (0 bytes when nothing was rewritten)
#   .events      one projected event per line, tab separated:
#                <body> TAB <display> [TAB matched=.. TAB available=.. TAB
#                names=.. TAB rewritten=..]
# The fixture is run as the relative path `Dockerfile` in a scratch directory.
# The prefix is s43_rdcopy_, not s43_migrate_ (that is the base#2055 partition).
# apply_migrations is the driver, so every event the dispatcher reports is
# captured; the warning goes to fd 2, hence 2>&1 into the raw event file.

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

# _regen_case <case> -- run apply_migrations on s43_rdcopy_<case>.Dockerfile
# and leave out.{dockerfile,files,events} in ${BATS_TEST_TMPDIR}/<case>/.
_regen_case() {
  local _name="s43_rdcopy_${1}" _d="${BATS_TEST_TMPDIR}/${1}"
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
      apply_migrations Dockerfile > raw.events 2>&1
      migrated_files > out.files
    ' _ "${LIB}"
  ) || return 1
  _project_events "${_d}/raw.events" > "${_d}/out.events"
  cp -- "${_d}/Dockerfile" "${_d}/out.dockerfile"
}

# _check_case <case> -- regenerate and compare each output with its golden.
_check_case() {
  local _name="s43_rdcopy_${1}" _d="${BATS_TEST_TMPDIR}/${1}" _e _bad=0
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

# why: the three per-file helper COPYs collapse into one directory COPY.
@test "s43 rdcopy golden: three per-file COPYs collapse" {
  run _check_case three
  assert_success
}

# why: a subset in any order at the pre-dist path collapses (flat_to_dist first).
@test "s43 rdcopy golden: a pre-dist subset collapses" {
  run _check_case subset
  assert_success
}

# why: one dir COPY per stage that had a helper COPY.
@test "s43 rdcopy golden: one dir COPY per stage" {
  run _check_case stages
  assert_success
}

# why: a statement hand-listing two helpers collapses to one source.
@test "s43 rdcopy golden: two helpers on one statement collapse" {
  run _check_case twosrc
  assert_success
}

# why: a hand-relocated destination is preserved.
@test "s43 rdcopy golden: a relocated destination is preserved" {
  run _check_case reloc
  assert_success
}

# why: the commented runtime-stage scaffold is rewritten too.
@test "s43 rdcopy golden: commented COPYs are collapsed" {
  run _check_case comment
  assert_success
}

# why: the already-collapsed dir COPY is the fixed point.
@test "s43 rdcopy golden: an already-collapsed dir COPY is unchanged" {
  run _check_case collapsed
  assert_success
}

# why: a backslash-continued statement is declined with a manual-fix warning.
@test "s43 rdcopy golden: a continued statement is declined with a warning" {
  run _check_case continued
  assert_success
}

# why: the shape the real consumers carry (flat path, logging.sh per stage).
@test "s43 rdcopy golden: the real consumer shape is healed" {
  run _check_case consumer
  assert_success
}

# ── literal expectations, independent of the goldens ────────────────────────

# why: the three-COPY collapse is a worked literal from the unit spec.
@test "s43 rdcopy golden: three dockerfile golden equals the literal" {
  run cat "${GOLDEN}/s43_rdcopy_three.dockerfile"
  assert_success
  assert_output "$(printf '%s\n%s' \
    'FROM busybox AS devel' \
    'COPY --chmod=0755 .base/dist/script/docker/runtime/ /usr/local/lib/base/')"
}

# why: one patch event then the dispatcher report, each a worked literal.
@test "s43 rdcopy golden: three events golden equals the literal events" {
  run cat "${GOLDEN}/s43_rdcopy_three.events"
  assert_success
  assert_output "$(printf '%s\n%s' \
    $'dockerfile_patched\t  Dockerfile patched: runtime helper COPYs collapsed into one directory COPY (#971)' \
    $'dockerfile_migrations_reported\t  Dockerfile migrations: 1 of 16 matched (runtime_dir_copy), 1 file(s) rewritten\tmatched=1\tavailable=16\tnames=runtime_dir_copy\trewritten=1')"
}

# why: a rewrite is recorded as the Dockerfile path, one line.
@test "s43 rdcopy golden: three files golden is the single path Dockerfile" {
  run cat "${GOLDEN}/s43_rdcopy_three.files"
  assert_output "Dockerfile"
}

# why: the relocated destination survives as /opt/base/.
@test "s43 rdcopy golden: reloc dockerfile golden keeps /opt/base/" {
  run cat "${GOLDEN}/s43_rdcopy_reloc.dockerfile"
  assert_output "$(printf '%s\n%s' \
    'FROM busybox AS devel' \
    'COPY --chmod=0755 .base/dist/script/docker/runtime/ /opt/base/')"
}

# why: the continued statement is left byte-for-byte and the warning is reported.
@test "s43 rdcopy golden: continued dockerfile golden equals its fixture, with the warning event" {
  cmp -- "${CORPUS}/s43_rdcopy_continued.Dockerfile" "${GOLDEN}/s43_rdcopy_continued.dockerfile"
  [[ ! -s "${GOLDEN}/s43_rdcopy_continued.files" ]]
  run grep -c '^dockerfile_needs_manual_fix	' "${GOLDEN}/s43_rdcopy_continued.events"
  assert_output "1"
}

# why: the fixed point is a no-op: 0-byte .files, dockerfile == fixture.
@test "s43 rdcopy golden: collapsed goldens are the fixed point" {
  cmp -- "${CORPUS}/s43_rdcopy_collapsed.Dockerfile" "${GOLDEN}/s43_rdcopy_collapsed.dockerfile"
  [[ ! -s "${GOLDEN}/s43_rdcopy_collapsed.files" ]]
  run cat "${GOLDEN}/s43_rdcopy_collapsed.events"
  assert_output $'dockerfile_migrations_reported\t  Dockerfile migrations: 0 of 16 matched (none), 0 file(s) rewritten\tmatched=0\tavailable=16\tnames=none\trewritten=0'
}

# ── the partition check ─────────────────────────────────────────────────────

# why: each rdcopy fixture has exactly the three goldens and no golden lacks a fixture.
@test "s43 rdcopy golden: every fixture has exactly its three goldens and no extra" {
  local _f _stem _e _bad=0
  for _f in "${CORPUS}"/s43_rdcopy_*.Dockerfile; do
    [[ -e "${_f}" ]] || continue
    _stem="$(basename -- "${_f}" .Dockerfile)"
    for _e in dockerfile files events; do
      if [[ ! -f "${GOLDEN}/${_stem}.${_e}" ]]; then
        echo "fixture with no golden: ${_stem}.${_e}" >&2
        _bad=1
      fi
    done
  done
  for _f in "${GOLDEN}"/s43_rdcopy_*; do
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
  for _stem in three subset stages twosrc reloc comment collapsed continued consumer; do
    [[ -f "${CORPUS}/s43_rdcopy_${_stem}.Dockerfile" ]] || {
      echo "fixture missing: s43_rdcopy_${_stem}" >&2
      _bad=1
    }
  done
  (( _bad == 0 ))
}
