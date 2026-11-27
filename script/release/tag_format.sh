#!/usr/bin/env bash
#
# tag_format.sh - refuse a version tag name outside vX.Y.Z / vX.Y.Z-rcN.
#
# Usage:
#   tag_format.sh <tag>
#
#   <tag>   a tag name (v0.43.0) or a full ref (refs/tags/v0.43.0-rc9)
#
# Exit 0 = valid; 1 = not a version tag, the format on stderr; 2 = no tag.
# Pure bash, no repo state. Called by the release job in self-test.yaml.

# Strict mode only when run directly; a sourcing caller keeps its own.
if [[ "${BASH_SOURCE[0]:-}" == "${0:-}" ]]; then
  set -euo pipefail
fi

# No leading zeros; RC numbers start at 1.
_TF_TAG_RE='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc[1-9][0-9]*)?$'

err() { printf '[tag-format] %s\n' "$*" >&2; }

# _tf_main <tag> -- check one tag name.
_tf_main() {
  local _ref="${1-}" _tag
  if [[ -z "${_ref}" ]]; then
    err "no tag given. Usage: tag_format.sh <tag>, e.g. v0.43.0 or refs/tags/v0.43.0-rc9."
    return 2
  fi
  _tag="${_ref#refs/tags/}"
  if [[ "${_tag}" =~ ${_TF_TAG_RE} ]]; then
    return 0
  fi
  err "'${_tag}' is not a version tag. Version tags are vX.Y.Z or vX.Y.Z-rcN (e.g. v0.43.0, v0.43.0-rc9): no leading zeros, N from 1. Pattern: ${_TF_TAG_RE}"
  return 1
}

if [[ "${BASH_SOURCE[0]:-}" == "${0:-}" ]]; then
  _tf_main "$@"
fi
