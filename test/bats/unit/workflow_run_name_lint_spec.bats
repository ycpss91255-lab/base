#!/usr/bin/env bats
#
# Unit tests for script/test/drivers/workflow_run_name.sh: every workflow
# under .github/workflows/ sets a top-level run-name that holds a ${{ }}
# expression. Runs over fixture trees only; the live tree is checked by the
# lint job itself.
#
# why: Unit tests for `script/test/drivers/workflow_run_name.sh`
# (`_run_workflow_run_name`), the "every workflow has a dynamic run-name"
# lint. Without a run-name every run in the Actions list shows only the
# workflow name, so a run cannot be traced to its PR, push or tag. Each case
# plants a small `.github/workflows/` tree and checks which shapes pass and
# which fail, including the ways the lint could pass having checked nothing.

setup() {
  export LOG_FORMAT=text
  load "${BATS_TEST_DIRNAME}/test_helper"

  # Driver sourced alone: test.sh makes REPO_ROOT readonly.
  # shellcheck disable=SC1091
  source /source/dist/script/docker/lib/_lib.sh
  _die() { local _ev="${1}"; shift; _log_err ci "${_ev}" "display=$*"; return 1; }
  # shellcheck disable=SC1091
  source /source/script/test/drivers/workflow_run_name.sh

  SCRATCH="$(mktemp -d)"
  REPO_ROOT="${SCRATCH}"
  WF_DIR="${SCRATCH}/.github/workflows"
  mkdir -p "${WF_DIR}"
}

teardown() {
  if [[ -n "${SCRATCH:-}" ]]; then
    rm -rf "${SCRATCH}"
  fi
}

# _write_wf <name> -- write stdin to .github/workflows/<name>.
_write_wf() {
  cat > "${WF_DIR}/${1}"
}

# _good_wf <name> -- a workflow with a one-line dynamic run-name.
_good_wf() {
  _write_wf "${1}" <<'EOF'
name: Good
run-name: "${{ github.event_name }} · ${{ github.ref_name || '?' }}"

on:
  push:

jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: true
EOF
}

# why: The shape every workflow here uses passes
@test "_run_workflow_run_name: a one-line dynamic run-name passes" {
  _good_wf good.yaml
  run _run_workflow_run_name
  assert_success
  assert_output --partial "clean"
}

# why: A missing run-name fails and names the file; an expression in another
# top-level key does not count
@test "_run_workflow_run_name: a workflow without run-name fails and is named" {
  _good_wf good.yaml
  _write_wf missing.yaml <<'EOF'
name: Missing

on:
  pull_request:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}

jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: true
EOF
  run _run_workflow_run_name
  assert_failure
  assert_output --partial "missing.yaml: no top-level run-name"
  refute_output --partial "good.yaml:"
}

# why: Static text is the default title spelled out, so it fails
@test "_run_workflow_run_name: a static run-name fails" {
  _write_wf static.yaml <<'EOF'
name: Static
run-name: CI run

on:
  push:

jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: true
EOF
  run _run_workflow_run_name
  assert_failure
  assert_output --partial "static.yaml: run-name has no"
}

# why: A folded block scalar is read across its lines
@test "_run_workflow_run_name: a folded dynamic run-name passes" {
  _write_wf folded.yaml <<'EOF'
name: Folded
run-name: >-
  ${{ github.event_name }} ·
  ${{ github.sha || '?' }}

on:
  push:

jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: true
EOF
  run _run_workflow_run_name
  assert_success
}

# why: A folded block with static lines only fails
@test "_run_workflow_run_name: a folded static run-name fails" {
  _write_wf folded.yaml <<'EOF'
name: Folded
run-name: >-
  CI
  run

on:
  push:

jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: true
EOF
  run _run_workflow_run_name
  assert_failure
  assert_output --partial "folded.yaml: run-name has no"
}

# why: A commented-out run-name is not a run-name
@test "_run_workflow_run_name: a commented-out run-name fails" {
  _write_wf commented.yaml <<'EOF'
name: Commented
# run-name: ${{ github.event_name }}

on:
  push:

jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: true
EOF
  run _run_workflow_run_name
  assert_failure
  assert_output --partial "commented.yaml: no top-level run-name"
}

# why: Only the top-level key names the run; an indented one does not
@test "_run_workflow_run_name: an indented run-name does not count" {
  _write_wf indented.yaml <<'EOF'
name: Indented

on:
  push:

jobs:
  a:
    run-name: ${{ github.event_name }}
    runs-on: ubuntu-latest
    steps:
      - run: true
EOF
  run _run_workflow_run_name
  assert_failure
  assert_output --partial "indented.yaml: no top-level run-name"
}

# why: GitHub also loads .yml files, so they are checked too
@test "_run_workflow_run_name: a .yml workflow is checked" {
  _good_wf good.yaml
  _write_wf other.yml <<'EOF'
name: Other

on:
  push:

jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: true
EOF
  run _run_workflow_run_name
  assert_failure
  assert_output --partial "other.yml: no top-level run-name"
}

# why: An empty or missing workflow directory must fail, not pass having
# checked nothing
@test "_run_workflow_run_name: zero workflow files fails" {
  run _run_workflow_run_name
  assert_failure
  assert_output --partial "no workflow files"
  rm -rf "${SCRATCH}/.github"
  run _run_workflow_run_name
  assert_failure
  assert_output --partial "no workflow files"
}

# why: A lint nobody runs is a comment
@test "workflow-run-name: is a member of the lint phase's tool table" {
  # Parsed, not sourced: sourcing test.sh breaks under kcov.
  local _test_sh="/source/script/test/test.sh"
  assert_spec_subject "${_test_sh}" "the test runner whose _LINT_TOOLS table this lint joins"
  run awk '
    /^readonly _LINT_TOOLS=\(/ { inside = 1; next }
    inside && /^\)/            { inside = 0 }
    inside {
      sub(/#.*/, "")
      gsub(/[[:space:]]+/, "")
      if ($0 != "") print
    }
  ' "${_test_sh}"
  assert_success
  assert_line "workflow-run-name"
}

# why: Exactly one lint-static group runs it: none gates nothing and two pay
# twice
@test "workflow-run-name: has a lint-static CI join" {
  local _wf="/source/.github/workflows/self-test.yaml"
  assert_spec_subject "${_wf}" "the workflow whose lint-static groups this lint joins"
  local _hits
  _hits="$(lint_group_hits workflow-run-name "${_wf}")"
  [ "${_hits}" -eq 1 ] \
    || fail "the workflow-run-name lint is in ${_hits} lint-static groups; with none, a workflow without a dynamic run-name merges unchecked"
}

# why: An unregistered event id is an anonymous exit
@test "workflow-run-name: its failure event id is registered" {
  run grep -qx 'ci_workflow_run_name' /source/dist/script/docker/lib/log-events.txt
  assert_success
}

# why: The driver must be dispatchable by the name the table carries
@test "workflow-run-name: the dispatcher has a case arm for it" {
  local _test_sh="/source/script/test/test.sh"
  assert_spec_subject "${_test_sh}" "the dispatcher whose _run_lint_tool arm this lint needs"
  run grep -qE '^[[:space:]]*workflow-run-name\)[[:space:]]*_run_workflow_run_name' \
    "${_test_sh}"
  assert_success
}
