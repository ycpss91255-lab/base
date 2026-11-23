#!/usr/bin/env bats
#
# doc_reader_specs_spec.bats -- script/ci/doc_reader_specs.sh lists every
# spec that reads the checkout's own documentation, base#2110.
#
# why: A documentation-only pull request skips coverage, the one job that
# runs these specs, so a doc edit that breaks one was first seen in the
# merge queue. The doc-counts job runs the list instead. A spec the list
# misses is a check nobody runs on that pull request, so the rules must
# err towards listing.

bats_require_minimum_version 1.5.0

setup() {
  load "${BATS_TEST_DIRNAME}/test_helper"
  LIST_SH=/source/script/ci/doc_reader_specs.sh
  # Spelled in two parts so this file's fixtures are not read as a
  # reference to the checkout itself.
  SRC="/sou""rce"
  TREE="${BATS_TEST_TMPDIR}/tree"
  mkdir -p "${TREE}/test/bats/unit/sub" "${TREE}/test/bats/integration" "${TREE}/test/bats/system"
}

# _spec <path> <line>... -- a fixture spec holding the lines.
_spec() {
  local _p="${TREE}/test/bats/$1"
  shift
  printf '%s\n' '#!/usr/bin/env bats' "$@" > "${_p}"
}

# why: each way a spec can reach a live document, by the document's kind:
# a literal path, a variable holding the checkout, a glob, a directory, a
# relative path after entering the tree, and a walk of the whole tree.
@test "doc_reader_specs: every way of reading a live document lists the spec (base#2110)" {
  local -a _lines=(
    "run cat ${SRC}/doc/guide/a.md"
    "README=\"${SRC}/README.md\""
    "run cat ${SRC}/CONTEXT.md"
    "[ -f ${SRC}/LICENSE ]"
    "for f in ${SRC}/doc/readme/README.*.md; do"
    "[ -d ${SRC}/doc ]"
    "done < <(find ${SRC} -name '*.md')"
    "run grep -rlF x ${SRC}"
    "run git -C \"${SRC}\" grep -n x \"${SRC}\""
  )
  local _i
  for _i in "${!_lines[@]}"; do
    _spec "unit/r${_i}_spec.bats" "${_lines[${_i}]}"
  done
  _spec unit/var_spec.bats "  REPO=${SRC}" '  run cat "${REPO}/doc/adr/1.md"'
  _spec unit/walk_spec.bats "  ROOT=\"${SRC}\"" '  run find "${ROOT}" -type f'
  _spec unit/cd_spec.bats "cd ${SRC}" 'run cat README.md'
  _spec integration/i_spec.bats "cat ${SRC}/doc/a.md"
  _spec unit/sub/nested_spec.bats "cat ${SRC}/doc/a.md"
  run bash "${LIST_SH}" "${TREE}"
  assert_success
  assert_output "$(cd "${TREE}" && find test/bats/unit test/bats/integration -name '*_spec.bats' | LC_ALL=C sort | sed -n '/unit/p')
test/bats/integration/i_spec.bats"
}

# why: a comment, a fixture's own doc path and another part of the checkout
# are not reads of a document, so the list does not grow into the whole
# suite. The system suite needs a docker socket and is never listed.
@test "doc_reader_specs: a comment, a fixture path, another tree and a system spec are not listed (base#2110)" {
  _spec unit/reader_spec.bats "cat ${SRC}/doc/a.md"
  _spec unit/comment_spec.bats "# reads ${SRC}/doc/a.md"
  _spec unit/fixture_spec.bats 'cat "${SCRATCH}/doc/a.md"'
  _spec unit/code_spec.bats "cat ${SRC}/script/ci/doctor.sh ${SRC}/docs"
  _spec system/s_spec.bats "cat ${SRC}/doc/a.md"
  run bash "${LIST_SH}" "${TREE}"
  assert_success
  assert_output test/bats/unit/reader_spec.bats
}

# why: an empty list would run nothing and read as a pass.
@test "doc_reader_specs: no listed spec is a failure (base#2110)" {
  _spec unit/a_spec.bats 'true'
  run bash "${LIST_SH}" "${TREE}"
  assert_failure
  run bash "${LIST_SH}" "${BATS_TEST_TMPDIR}/nowhere"
  assert_failure
}

# why: the list over the real tree. Each of these specs opens a document of
# the checkout (read from its body), so a rule that stops seeing one of
# them fails here. The list may hold more.
@test "doc_reader_specs: the real tree's known document readers are listed, and each path exists (base#2110)" {
  local _s
  run bash "${LIST_SH}"
  assert_success
  for _s in adr_doc_claims changelog_entry_lint compose_emit/overlay_guard \
            coverage_badge doc_counts init org_name publish_worker_yaml \
            readme_file_table readme_sync release_notes self_test_yaml \
            template triage_label_yaml; do
    assert_line "test/bats/unit/${_s}_spec.bats"
  done
  while IFS= read -r _s; do
    assert [ -f "/source/${_s}" ]
  done <<<"${output}"
}
