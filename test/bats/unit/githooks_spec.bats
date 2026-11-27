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

# _push_hook -- run the hook from the fixture repo the way git does.
_push_hook() {
  run bash -c 'cd "$1" && "$2" origin https://example.invalid/repo.git </dev/null' _ "${REPO}" "${HOOK}"
}

# why: The hook blocks a push when a workflow has no dynamic run-name
@test "pre-push: blocks when a workflow lacks a dynamic run-name" {
  assert_spec_subject "${HOOK}" "the tracked pre-push hook"
  _wf good.yaml "run-name: \${{ github.event_name }}"
  _wf bad.yaml "run-name: static"
  _push_hook
  assert_failure
  assert_output --partial "bad.yaml: run-name has no"
  refute_output --partial "good.yaml:"
}

# why: The hook blocks a workflow with no run-name at all
@test "pre-push: blocks when a workflow has no run-name" {
  _wf missing.yaml ""
  _push_hook
  assert_failure
  assert_output --partial "missing.yaml: no top-level run-name"
}

# why: The hook lets a push through when every workflow passes
@test "pre-push: allows the push when every workflow has a dynamic run-name" {
  _wf a.yaml "run-name: \${{ github.event_name }}"
  _wf b.yml "run-name: \${{ github.ref_name || '?' }}"
  _push_hook
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
