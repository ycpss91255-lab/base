#!/usr/bin/env bats
#
# config_gen_s93_mount_golden_spec.bats -- the s93 corpus of volume mount
# specs against what today's shell makes of them (base#2081, S93e of
# base#1829 under base#1395).
#
# why: Before any Go code takes the host path out of a mount spec, the
# shell's reading is pinned. testdata/corpus/s93/s93_mount_specs.txt holds one
# spec per line; testdata/golden/s93/s93_mount_specs.golden holds, per spec,
# the line `_mount_host_path` (dist/script/docker/lib/_tui_conf.sh) leaves in
# its outvar. The spec regenerates the golden from the shell and fails on any
# byte difference, on a missing corpus or golden, and on a line count that
# differs between the two.

bats_require_minimum_version 1.5.0

setup() {
  load "${BATS_TEST_DIRNAME}/../unit/test_helper"
  TESTDATA="/source/dockerfile/config-gen/testdata"
  CORPUS="${TESTDATA}/corpus/s93/s93_mount_specs.txt"
  GOLDEN="${TESTDATA}/golden/s93/s93_mount_specs.golden"
}

# _mount_result -- print, for each line of the corpus, what _mount_host_path
# leaves in its outvar, then a newline.
_mount_result() {
  local _spec
  while IFS= read -r _spec || [[ -n "${_spec}" ]]; do
    SPEC="${_spec}" bash -c '
      source /source/dist/script/docker/lib/_tui_conf.sh
      _mount_host_path "${SPEC}" _out
      printf "%s\n" "${_out}"
    '
  done < "${CORPUS}"
}

# why: a missing corpus or golden would silently pin nothing.
@test "s93: the mount spec corpus and golden exist" {
  [[ -f "${CORPUS}" ]] || { echo "missing corpus: s93_mount_specs"; return 1; }
  [[ -f "${GOLDEN}" ]] || { echo "missing golden: s93_mount_specs"; return 1; }
}

# why: the inputs must be the issue's own, in the issue's order, or the golden
# pins other cases (base#2081): ro option, no colon, leading colon, empty
# line, an unexpanded ${HOME}, and extra colons.
@test "s93: the mount spec corpus holds the issue's six specs" {
  local _want
  _want=$'/h/a:/c/a:ro\n/h/a\n:/c\n\n${HOME}/x:/y\na:b:c\n'
  [[ -f "${CORPUS}" ]] || { echo "missing corpus: s93_mount_specs"; return 1; }
  [ "$(cat -- "${CORPUS}"; echo x)" = "${_want}x" ]
}

# why: _mount_host_path keeps the text before the first colon; the shell
# result must match the golden byte for byte.
@test "s93: _mount_host_path result matches the golden" {
  [[ -f "${CORPUS}" ]] || { echo "missing corpus: s93_mount_specs"; return 1; }
  [[ -f "${GOLDEN}" ]] || { echo "corpus with no golden: s93_mount_specs"; return 1; }
  _mount_result > "${BATS_TEST_TMPDIR}/got"
  cmp -- "${BATS_TEST_TMPDIR}/got" "${GOLDEN}"
}

# why: the worked results come from the issue, not from the shell.
@test "s93: the mount golden holds the issue's six results" {
  local _want
  _want=$'/h/a\n/h/a\n\n\n${HOME}/x\na\n'
  [[ -f "${GOLDEN}" ]] || { echo "missing golden: s93_mount_specs"; return 1; }
  [ "$(cat -- "${GOLDEN}"; echo x)" = "${_want}x" ]
}

# why: one golden line per corpus line, or a spec is unpinned.
@test "s93: the mount golden has as many lines as the corpus" {
  [[ -f "${CORPUS}" ]] || { echo "missing corpus: s93_mount_specs"; return 1; }
  [[ -f "${GOLDEN}" ]] || { echo "missing golden: s93_mount_specs"; return 1; }
  [ "$(wc -l < "${GOLDEN}")" -eq "$(wc -l < "${CORPUS}")" ]
}
