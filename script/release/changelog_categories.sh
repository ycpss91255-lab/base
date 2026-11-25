#!/usr/bin/env bash
#
# changelog_categories.sh - the locked changelog category roster, in the
# order a release page emits them: BREAKING plus the Keep a Changelog six.
#
# Applies to [Unreleased] only; a released heading is not rewritten.
#
# Sourceable: no main, no strict mode at file scope.

# The roster, in emission order.
# shellcheck disable=SC2034  # read by the files that source this one.
CHANGELOG_CATEGORIES=(
  BREAKING
  Added
  Changed
  Deprecated
  Removed
  Fixed
  Security
)
