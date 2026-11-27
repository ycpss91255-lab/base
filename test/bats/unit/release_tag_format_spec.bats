#!/usr/bin/env bats
#
# release_tag_format_spec.bats -- script/release/tag_format.sh: the one
# check of a version tag's name.
#
# why: Release notes, RC lookup and downstream upgrade all read a tag as
# `vX.Y.Z` or `vX.Y.Z-rcN`. A tag in any other shape publishes a release
# those tools misread, so the name is refused before anything is published.

bats_require_minimum_version 1.5.0

setup() {
  load "${BATS_TEST_DIRNAME}/test_helper"
  CHECK=/source/script/release/tag_format.sh
  TAGS=/source/test/fixtures/release_tags.txt
  assert_spec_subject "${CHECK}" "the version tag name check"
  assert_spec_subject "${TAGS}" "the list of tags already published"
}

# why: The accepted shapes. A check that refuses a real release tag would
# fail the release it exists to protect.
@test "tag_format.sh: vX.Y.Z and vX.Y.Z-rcN pass" {
  local _t
  for _t in v0.43.0 v1.2.3-rc1 v0.43.0-rc12 v0.0.0 v10.20.30-rc100; do
    run "${CHECK}" "${_t}"
    [[ "${status}" -eq 0 ]] || fail "refused ${_t}: ${output}"
  done
}

# why: Each name is one way a tag goes wrong: missing patch, no `v`, a
# dotted or zero RC number, a leading zero, a non-version name.
@test "tag_format.sh: every other name is refused with the format printed" {
  local _t
  for _t in v1.0 release-1 v1.2.3-rc.1 v1.2.3-rc0 v01.2.3 1.2.3 \
      v1.02.3 v1.2.03 v1.2.3-rc01 v1.2.3-beta1 v1.2.3+build.5 \
      v1.2.3-rc 'v1.2.3 ' V1.2.3 v1.2.3.4; do
    run "${CHECK}" "${_t}"
    [[ "${status}" -eq 1 ]] || fail "'${_t}' exited ${status}, want 1: ${output}"
    [[ "${output}" == *"'${_t}'"* ]] || fail "message does not name '${_t}': ${output}"
    [[ "${output}" == *'vX.Y.Z-rcN'* ]] || fail "message does not print the format: ${output}"
  done
}

# why: The pre-push hook holds a full remote ref, the release job a bare
# tag name; both must get the same answer.
@test "tag_format.sh: a refs/tags/ ref is checked by its tag name" {
  run "${CHECK}" refs/tags/v1.2.3-rc1
  assert_success
  run "${CHECK}" refs/tags/v1.0
  assert_failure 1
  run "${CHECK}" refs/heads/v1.2.3
  assert_failure 1
}

# why: A missing name must not read as a valid one.
@test "tag_format.sh: no tag or an empty tag is a usage error" {
  run "${CHECK}"
  assert_failure 2
  run "${CHECK}" ''
  assert_failure 2
  run "${CHECK}" refs/tags/
  assert_failure 1
}

# why: The format was chosen to fit every tag already published. If one
# failed, the rule would refuse a shape that already shipped.
@test "tag_format.sh: every published tag passes" {
  local _t _n=0
  while IFS= read -r _t; do
    [[ -n "${_t}" ]] || continue
    _n=$(( _n + 1 ))
    run "${CHECK}" "${_t}"
    [[ "${status}" -eq 0 ]] || fail "published tag ${_t} is refused: ${output}"
  done < "${TAGS}"
  [[ "${_n}" -ge 139 ]] || fail "only ${_n} tags read from ${TAGS}; the list was emptied or cut"
}
