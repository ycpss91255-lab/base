#!/usr/bin/env bats
#
# config_gen_s72_interval_golden_spec.bats -- the s72 corpus of version
# migration declarations against what today's shell selects from it
# (base#2301, S72b of base#1807 under base#1395).
#
# why: Before any Go code selects migrations, the shell's selection and order
# are pinned. The corpus file testdata/corpus/s72/s72_interval_decl.txt holds
# one declaration per line ("<version> <name>", in declaration order); the
# golden testdata/golden/s72/s72_interval_decl.golden holds, per interval, a
# "<from> -> <to>" line, the stdout lines of interval_migrations indented by
# two spaces, a "warn=<n>" line (the count of interval_migration_declined
# warnings on stderr; their text is not pinned) and "rc=<exit code>"
# (dist/script/docker/lib/version_migrate.sh). The spec regenerates the
# golden from the shell and fails on any byte difference, on a corpus with no
# golden, and on a golden with no corpus.

bats_require_minimum_version 1.5.0

setup() {
  load "${BATS_TEST_DIRNAME}/../unit/test_helper"
  TESTDATA="/source/dockerfile/config-gen/testdata"
  CORPUS="${TESTDATA}/corpus/s72"
  GOLDEN="${TESTDATA}/golden/s72"
  STEM=s72_interval_decl
}

# _shell_result -- print, for each interval, the golden section the shell
# yields. The declarations are read from the corpus into _VERSION_MIGRATIONS;
# _vmigrate_a_apply and _vmigrate_b_apply are empty functions, and "nofn" has
# none.
_shell_result() {
  local _pair _from _to _out _rc _warn _line
  for _pair in \
    "v0.41.0 v0.43.0" "v0.42.0 v0.43.0" "v0.43.0 v0.43.0" \
    "v0.9.7 v0.10.0" "v0.43.0-rc1 v0.43.0" "v0.1.0 v0.2.0"; do
    _from="${_pair% *}"
    _to="${_pair#* }"
    _rc=0
    CORPUS_FILE="${CORPUS}/${STEM}.txt" FROM="${_from}" TO="${_to}" \
      bash -c '
        source /source/dist/script/docker/lib/log.sh
        source /source/dist/script/docker/lib/version_migrate.sh
        _VERSION_MIGRATIONS=()
        while IFS= read -r _l || [[ -n "${_l}" ]]; do
          _VERSION_MIGRATIONS+=("${_l}")
        done < "${CORPUS_FILE}"
        _vmigrate_a_apply() { :; }
        _vmigrate_b_apply() { :; }
        interval_migrations "${FROM}" "${TO}"
      ' > "${BATS_TEST_TMPDIR}/out" 2> "${BATS_TEST_TMPDIR}/err" || _rc=$?
    _warn="$(grep -c 'interval_migration_declined' "${BATS_TEST_TMPDIR}/err" || true)"
    printf '%s -> %s\n' "${_from}" "${_to}"
    while IFS= read -r _line || [[ -n "${_line}" ]]; do
      printf '  %s\n' "${_line}"
    done < "${BATS_TEST_TMPDIR}/out"
    printf 'warn=%s\n' "${_warn}"
    printf 'rc=%s\n' "${_rc}"
  done
}

# why: a missing corpus or golden would silently pin nothing.
@test "s72: the interval_decl corpus and golden exist" {
  [[ -f "${CORPUS}/${STEM}.txt" ]] || { echo "missing corpus: ${STEM}"; return 1; }
  [[ -f "${GOLDEN}/${STEM}.golden" ]] || { echo "missing golden: ${STEM}"; return 1; }
}

# why: the declarations must be the issue's own seven, in its order, or the
# golden pins other cases (base#2301).
@test "s72: the corpus holds the issue's seven declarations" {
  local _want
  _want=$'v0.42.0 a\nv0.43.0 b\nv0.42.0 b\nv0.10.0 a\nv0.43.0-rc1 a\n'
  _want+=$'bad\nv0.44.0 nofn\n'
  [[ -f "${CORPUS}/${STEM}.txt" ]] || { echo "missing corpus: ${STEM}"; return 1; }
  [ "$(cat -- "${CORPUS}/${STEM}.txt"; echo x)" = "${_want}x" ]
}

# why: the worked results come from the issue's table, not from the shell.
# Both declined declarations warn on every call, so warn=2 throughout.
@test "s72: the golden holds the issue's results" {
  local _want
  _want=$'v0.41.0 -> v0.43.0\n'
  _want+=$'  v0.42.0 a\n  v0.42.0 b\n  v0.43.0 b\n  v0.43.0-rc1 a\n'
  _want+=$'warn=2\nrc=0\n'
  _want+=$'v0.42.0 -> v0.43.0\n  v0.43.0 b\n  v0.43.0-rc1 a\nwarn=2\nrc=0\n'
  _want+=$'v0.43.0 -> v0.43.0\nwarn=2\nrc=0\n'
  _want+=$'v0.9.7 -> v0.10.0\n  v0.10.0 a\nwarn=2\nrc=0\n'
  _want+=$'v0.43.0-rc1 -> v0.43.0\nwarn=2\nrc=0\n'
  _want+=$'v0.1.0 -> v0.2.0\nwarn=2\nrc=0\n'
  [[ -f "${GOLDEN}/${STEM}.golden" ]] || { echo "missing golden: ${STEM}"; return 1; }
  [ "$(cat -- "${GOLDEN}/${STEM}.golden"; echo x)" = "${_want}x" ]
}

# why: interval_migrations must select and order the corpus the way the
# golden says; the shell result must match it byte for byte.
@test "s72: the shell result matches the golden" {
  [[ -f "${CORPUS}/${STEM}.txt" ]] || { echo "missing corpus: ${STEM}"; return 1; }
  [[ -f "${GOLDEN}/${STEM}.golden" ]] || { echo "missing golden: ${STEM}"; return 1; }
  _shell_result > "${BATS_TEST_TMPDIR}/got"
  cmp -- "${BATS_TEST_TMPDIR}/got" "${GOLDEN}/${STEM}.golden"
}

# why: a golden whose corpus file was deleted would stand for nothing.
@test "s72: every golden has a corpus file" {
  local _g _stem _bad=0
  for _g in "${GOLDEN}"/*.golden; do
    [[ -e "${_g}" ]] || continue
    _stem="$(basename -- "${_g}" .golden)"
    if [[ ! -f "${CORPUS}/${_stem}.txt" ]]; then
      printf 'golden with no corpus: %s\n' "${_stem}"
      _bad=1
    fi
  done
  [ "${_bad}" -eq 0 ]
}

# why: a corpus file with no golden would pin nothing; and with no files at
# all the loops above pass vacuously.
@test "s72: every corpus file has a golden" {
  local _f _stem _n=0 _bad=0
  for _f in "${CORPUS}"/*.txt; do
    [[ -e "${_f}" ]] || continue
    _n=$((_n + 1))
    _stem="$(basename -- "${_f}" .txt)"
    if [[ ! -f "${GOLDEN}/${_stem}.golden" ]]; then
      printf 'corpus with no golden: %s\n' "${_stem}"
      _bad=1
    fi
  done
  [ "${_n}" -ge 1 ] || { echo "no s72 corpus files"; return 1; }
  [ "${_bad}" -eq 0 ]
}
