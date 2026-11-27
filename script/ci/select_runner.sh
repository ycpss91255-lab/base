#!/usr/bin/env bash
# select_runner.sh - Say whether the code of this event is trusted enough
# for a self-hosted runner.
#
# Usage: EVENT_NAME=<event> REPO=<owner/name> [HEAD_REPO=<owner/name>] \
#          [MERGE_GROUP_SAME_REPO=true|false] [CI_SELF_HOSTED=cpu] \
#          select_runner.sh
#
# Prints two lines on stdout and always exits 0: `trusted=true|false`, then
# `runs_on=<compact JSON array>`. runs_on is the cpu fleet
# `["self-hosted","linux","x64","cpu"]` only when the event is trusted and
# CI_SELF_HOSTED is exactly `cpu`; every other case is `["ubuntu-latest"]`,
# so unsetting the switch falls back to the hosted pool, base#2266.
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

if [[ -z "${EVENT_NAME:-}" ]]; then
  printf '::error::select_runner: EVENT_NAME is not set\n' >&2
  printf 'trusted=false\n'
  printf 'runs_on=["ubuntu-latest"]\n'
  exit 0
fi
if [[ -z "${REPO:-}" ]]; then
  printf '::error::select_runner: REPO is not set\n' >&2
  printf 'trusted=false\n'
  printf 'runs_on=["ubuntu-latest"]\n'
  exit 0
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

runs_on='["ubuntu-latest"]'
if [[ "${trusted}" == "true" && "${CI_SELF_HOSTED:-}" == "cpu" ]]; then
  runs_on='["self-hosted","linux","x64","cpu"]'
fi

printf 'trusted=%s\n' "${trusted}"
printf 'runs_on=%s\n' "${runs_on}"
