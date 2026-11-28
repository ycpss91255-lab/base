#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
. /usr/local/lib/base/logging.sh
export MY_APP_HOME=/opt/app
exec "${@}"
