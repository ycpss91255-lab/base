#!/usr/bin/env bats
#
# Unit tests for the tracked git hooks: .githooks/pre-push and
# script/githooks/install.sh. Every case runs in a throwaway git repo with
# HOME pointed at a scratch dir, so no real config is read or written.
#
# why: Unit tests for the local git hooks (`.githooks/pre-push`) and their
# installer (`script/githooks/install.sh`). The pre-push hook is the first,
# local gate for the workflow run-name rule and must run the same driver CI
# runs; CI stays the real gate. The installer is the one command that turns
# the hooks on for a checkout, sets only this repo's config, and refuses to
# silently disable hooks that are already in use.

setup() {
  load "${BATS_TEST_DIRNAME}/test_helper"

  HOOK="/source/.githooks/pre-push"
  INSTALL="/source/script/githooks/install.sh"

  SCRATCH="$(mktemp -d)"
  export HOME="${SCRATCH}/home"
  mkdir -p "${HOME}"
  export GIT_CONFIG_NOSYSTEM=1
  unset GIT_CONFIG_GLOBAL

  ZERO_SHA="0000000000000000000000000000000000000000"
  REPO="${SCRATCH}/repo"
  git init -q "${REPO}"
  mkdir -p "${REPO}/.github/workflows"
}

teardown() {
  if [[ -n "${SCRATCH:-}" ]]; then
    rm -rf "${SCRATCH}"
  fi
}

# _wf <name> <run-name line or empty> -- plant a workflow in the fixture repo.
_wf() {
  {
    printf 'name: Fixture\n'
    [[ -z "${2}" ]] || printf '%s\n' "${2}"
    printf 'on:\n  push:\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n'
  } > "${REPO}/.github/workflows/${1}"
}

# _commit -- commit the fixture repo's tree; prints the new commit sha.
_commit() {
  git -C "${REPO}" add -A
  git -C "${REPO}" -c user.name=fixture -c user.email=fixture@example.invalid \
    commit -q --no-gpg-sign -m fixture
  git -C "${REPO}" rev-parse HEAD
}

# _push_hook <stdin lines> -- run the hook from the fixture repo the way git
# does: remote name and url as arguments, one ref line per pushed ref on stdin.
_push_hook() {
  run bash -c 'cd "$1" && printf "%s" "$3" | "$2" origin https://example.invalid/repo.git' \
    _ "${REPO}" "${HOOK}" "${1}"
}

# _ref_line <local sha> -- the stdin line git writes for pushing main.
_ref_line() {
  printf 'refs/heads/main %s refs/heads/main %s\n' "${1}" "${ZERO_SHA}"
}

# why: The hook blocks a push when a workflow has no dynamic run-name
@test "pre-push: blocks when a workflow lacks a dynamic run-name" {
  assert_spec_subject "${HOOK}" "the tracked pre-push hook"
  _wf good.yaml "run-name: \${{ github.event.merge_group.head_ref || github.event_name }}"
  _wf bad.yaml "run-name: static"
  _push_hook "$(_ref_line "$(_commit)")"
  assert_failure
  assert_output --partial "bad.yaml: run-name has no"
  refute_output --partial "good.yaml:"
}

# why: The hook blocks a workflow with no run-name at all
@test "pre-push: blocks when a workflow has no run-name" {
  _wf missing.yaml ""
  _push_hook "$(_ref_line "$(_commit)")"
  assert_failure
  assert_output --partial "missing.yaml: no top-level run-name"
}

# why: The hook lets a push through when every workflow passes
@test "pre-push: allows the push when every workflow has a dynamic run-name" {
  _wf a.yaml "run-name: \${{ github.event.merge_group.head_ref || github.event_name }}"
  _wf b.yml "run-name: \${{ github.event.merge_group.head_ref || github.ref_name || '?' }}"
  _push_hook "$(_ref_line "$(_commit)")"
  assert_success
}

# why: The hook checks the commit being pushed, not the working tree: a
# fix that is only in the working tree does not reach the remote
@test "pre-push: blocks a pushed commit that is bad even when the working tree is fixed" {
  _wf a.yaml "run-name: static"
  local _sha
  _sha="$(_commit)"
  _wf a.yaml "run-name: \${{ github.event.merge_group.head_ref || github.event_name }}"
  _push_hook "$(_ref_line "${_sha}")"
  assert_failure
  assert_output --partial "a.yaml: run-name has no"
}

# why: An unstaged mistake in the working tree is not what is pushed, so it
# does not block a good commit
@test "pre-push: allows a pushed commit that is good even when the working tree is broken" {
  _wf a.yaml "run-name: \${{ github.event.merge_group.head_ref || github.event_name }}"
  local _sha
  _sha="$(_commit)"
  _wf a.yaml "run-name: static"
  _push_hook "$(_ref_line "${_sha}")"
  assert_success
}

# why: Deleting a remote branch pushes no commit, so there is nothing to check
@test "pre-push: a branch deletion is not checked" {
  _wf a.yaml "run-name: static"
  local _sha
  _sha="$(_commit)"
  _push_hook "$(printf '(delete) %s refs/heads/old %s\n' "${ZERO_SHA}" "${_sha}")"
  assert_success
}

_good_commit() {
  _wf a.yaml "run-name: \${{ github.event.merge_group.head_ref || github.event_name }}"
  _commit
}

_tag_line() {
  printf 'refs/tags/%s %s refs/tags/%s %s\n' "${1}" "${2}" "${1}" "${ZERO_SHA}"
}

# why: A tag outside vX.Y.Z / vX.Y.Z-rcN is stopped before it reaches the
# remote, with the format printed, instead of failing the release later.
@test "pre-push: blocks a tag whose name is not vX.Y.Z or vX.Y.Z-rcN" {
  local _t _sha
  _sha="$(_good_commit)"
  for _t in v1.0 release-1 v1.2.3-rc.1; do
    _push_hook "$(_tag_line "${_t}" "${_sha}")"
    assert_failure
    assert_output --partial "'${_t}' is not a version tag"
    assert_output --partial "vX.Y.Z-rcN"
  done
  # A valid tag in the same push does not let the bad one through.
  _push_hook "$(_tag_line v1.2.3 "${_sha}"; _tag_line release-1 "${_sha}")"
  assert_failure
  assert_output --partial "'release-1' is not a version tag"
}

# why: The accepted shapes must still push.
@test "pre-push: allows a tag named vX.Y.Z or vX.Y.Z-rcN" {
  local _sha
  _sha="$(_good_commit)"
  _push_hook "$(_tag_line v1.2.3-rc1 "${_sha}")"
  assert_success
  _push_hook "$(_tag_line v1.2.3 "${_sha}")"
  assert_success
}

# why: Deleting a badly named tag is how it gets cleaned up, so it is never
# blocked.
@test "pre-push: a tag deletion is not checked" {
  local _sha
  _sha="$(_good_commit)"
  _push_hook "$(printf '(delete) %s refs/tags/v1.0 %s\n' "${ZERO_SHA}" "${_sha}")"
  assert_success
}

# why: The name rule is for tags; a branch called v1.0 is not a release.
@test "pre-push: a branch named like a bad tag is not checked as a tag" {
  local _sha
  _sha="$(_good_commit)"
  _push_hook "$(printf 'refs/heads/v1.0 %s refs/heads/v1.0 %s\n' "${_sha}" "${ZERO_SHA}")"
  assert_success
}

# why: `git push --follow-tags` sends the branch and its tag on one commit;
# skipping a commit already checked must not skip the tag's name.
@test "pre-push: a bad tag on a commit already pushed in the same push is still blocked" {
  local _sha
  _sha="$(_good_commit)"
  _push_hook "$(_ref_line "${_sha}"; _tag_line release-1 "${_sha}")"
  assert_failure
  assert_output --partial "'release-1' is not a version tag"
}

# why: `git push origin v1.2.3:refs/tags/v1.0` creates `v1.0` on the remote;
# the name that matters is the remote ref, not the local one.
@test "pre-push: the pushed tag name is the remote ref, not the local one" {
  local _sha
  _sha="$(_good_commit)"
  _push_hook "$(printf 'refs/tags/v1.2.3 %s refs/tags/v1.0 %s\n' "${_sha}" "${ZERO_SHA}")"
  assert_failure
  assert_output --partial "'v1.0' is not a version tag"
  assert_output --partial "pre-push: refused tag refs/tags/v1.0 (pushed from refs/tags/v1.2.3)"
  _push_hook "$(printf 'refs/tags/v1.0 %s refs/tags/v1.2.3 %s\n' "${_sha}" "${ZERO_SHA}")"
  assert_success
}

# why: The hook must be executable in the index, or git skips it on Linux
# and macOS checkouts
@test "pre-push: is tracked as an executable file" {
  [ -x "${HOOK}" ] || fail "${HOOK} is not executable"
  # /source is not always a git worktree; check the index mode where it is.
  git -c safe.directory='*' -C /source rev-parse --git-dir >/dev/null 2>&1 \
    || return 0
  run git -c safe.directory='*' -C /source ls-files -s .githooks/pre-push
  assert_success
  assert_output --regexp '^100755 '
}

# why: One command turns the hooks on, in this repo's own config only
@test "install: sets core.hooksPath to .githooks in the local config" {
  assert_spec_subject "${INSTALL}" "the hooks installer"
  run bash -c 'cd "$1" && "$2"' _ "${REPO}" "${INSTALL}"
  assert_success
  run git -C "${REPO}" config --local --get core.hooksPath
  assert_output ".githooks"
  run git config --global --get core.hooksPath
  assert_failure
}

# why: Running the installer twice is harmless
@test "install: is idempotent" {
  git -C "${REPO}" config --local core.hooksPath .githooks
  run bash -c 'cd "$1" && "$2"' _ "${REPO}" "${INSTALL}"
  assert_success
  run git -C "${REPO}" config --local --get core.hooksPath
  assert_output ".githooks"
}

# why: A hooks path already set elsewhere is not overwritten, so hooks the
# contributor already relies on keep running
@test "install: refuses to replace another core.hooksPath" {
  git -C "${REPO}" config --local core.hooksPath other-hooks
  run bash -c 'cd "$1" && "$2"' _ "${REPO}" "${INSTALL}"
  assert_failure
  assert_output --partial "other-hooks"
  run git -C "${REPO}" config --local --get core.hooksPath
  assert_output "other-hooks"
}

# why: Setting core.hooksPath stops .git/hooks from running, so an active
# hook there is a refusal unless --force says it may stop
@test "install: refuses when .git/hooks has an active hook, --force overrides" {
  printf '#!/bin/sh\nexit 0\n' > "${REPO}/.git/hooks/pre-commit"
  chmod +x "${REPO}/.git/hooks/pre-commit"
  run bash -c 'cd "$1" && "$2"' _ "${REPO}" "${INSTALL}"
  assert_failure
  assert_output --partial "pre-commit"
  run git -C "${REPO}" config --local --get core.hooksPath
  assert_failure
  run bash -c 'cd "$1" && "$2" --force' _ "${REPO}" "${INSTALL}"
  assert_success
  run git -C "${REPO}" config --local --get core.hooksPath
  assert_output ".githooks"
}

# why: The verify step says whether the hooks are active, by exit status
@test "install --check: fails before install and passes after" {
  run bash -c 'cd "$1" && "$2" --check' _ "${REPO}" "${INSTALL}"
  assert_failure
  assert_output --partial "not active"
  git -C "${REPO}" config --local core.hooksPath .githooks
  run bash -c 'cd "$1" && "$2" --check' _ "${REPO}" "${INSTALL}"
  assert_success
  assert_output --partial "active"
}

# why: Other repos, such as the ones the suite creates, never get the hooks
@test "install: a different fresh repo stays without core.hooksPath" {
  run bash -c 'cd "$1" && "$2"' _ "${REPO}" "${INSTALL}"
  assert_success
  git init -q "${SCRATCH}/other"
  run git -C "${SCRATCH}/other" config --get core.hooksPath
  assert_failure
}
