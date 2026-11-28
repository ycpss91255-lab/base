#!/usr/bin/env bash
# select_runner.sh - Say whether the code of this event is trusted enough
# for a self-hosted runner.
#
# Usage: EVENT_NAME=<event> REPO=<owner/name> [HEAD_REPO=<owner/name>] \
#          [MERGE_GROUP_SAME_REPO=true|false] [CI_SELF_HOSTED=cpu|off] \
#          select_runner.sh
#
# Prints two lines on stdout and always exits 0: `trusted=true|false`, then
# `runs_on=<compact JSON array>`. runs_on is the cpu fleet
# `["self-hosted","linux","x64","cpu"]` only when the event is trusted and
# CI_SELF_HOSTED is unset, empty or `cpu`; every other case is
# `["ubuntu-latest"]`, so setting the switch to `off` falls back to the
# hosted pool, base#2266, base#2287. FLEET_STUCK=true (the verdict of
# fleet_stuck.sh) also forces hosted and prints a ::notice:: on stderr;
# `trusted` is unchanged; other non-false values warn and are ignored,
# base#2316.
#
# push (a tag push is a push), workflow_dispatch, a pull_request whose head
# repository equals REPO, and a merge_group whose MERGE_GROUP_SAME_REPO is
# `true` are trusted. A fork, an empty head repository, an unproven
# merge_group and every unlisted event are not, base#2265 (part of
# base#1586).
#
# A missing EVENT_NAME or REPO proves nothing: it prints an `::error::`
# line on stderr naming the variable, answers false, and exits 0.
set -euo pipefail

readonly HOSTED_RUNS_ON='["ubuntu-latest"]'
readonly CPU_RUNS_ON='["self-hosted","linux","x64","cpu"]'

# _fail_closed <message>: name the missing input on stderr and answer hosted.
_fail_closed() {
  printf '::error::select_runner: %s\n' "$1" >&2
  printf 'trusted=false\n'
  printf 'runs_on=%s\n' "${HOSTED_RUNS_ON}"
  exit 0
}

if [[ -z "${EVENT_NAME:-}" ]]; then
  _fail_closed 'EVENT_NAME is not set'
fi
if [[ -z "${REPO:-}" ]]; then
  _fail_closed 'REPO is not set'
fi

trusted=false
case "${EVENT_NAME}" in
  push | workflow_dispatch)
    trusted=true
    ;;
  pull_request)
    if [[ -n "${HEAD_REPO:-}" && "${HEAD_REPO}" == "${REPO}" ]]; then
      trusted=true
    fi
    ;;
  merge_group)
    if [[ "${MERGE_GROUP_SAME_REPO:-}" == "true" ]]; then
      trusted=true
    fi
    ;;
esac

runs_on="${HOSTED_RUNS_ON}"
# Default-on (base#2287): unset or empty means cpu; only `off` or another value falls back.
if [[ "${trusted}" == "true" && ( -z "${CI_SELF_HOSTED:-}" || "${CI_SELF_HOSTED}" == "cpu" ) ]]; then
  runs_on="${CPU_RUNS_ON}"
fi

# base#2316: fleet_stuck.sh verdict. Only `true` moves runs to hosted; any
# other non-empty value except `false` is ignored with a warning.
case "${FLEET_STUCK:-}" in
  true)
    runs_on="${HOSTED_RUNS_ON}"
    printf '::notice::select_runner: cpu fleet stuck, using ubuntu-latest\n' >&2
    ;;
  "" | false) ;;
  *)
    printf '::warning::select_runner: FLEET_STUCK=%s ignored\n' "${FLEET_STUCK}" >&2
    ;;
esac

printf 'trusted=%s\n' "${trusted}"
printf 'runs_on=%s\n' "${runs_on}"
