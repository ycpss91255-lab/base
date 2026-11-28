ARG BASE_IMAGE
FROM ${BASE_IMAGE} AS runtime
COPY --chmod=0755 .base/script/docker/runtime/logging.sh /usr/local/lib/base/logging.sh

FROM ${BASE_IMAGE} AS devel
COPY --chmod=0755 .base/script/docker/runtime/logging.sh /usr/local/lib/base/logging.sh

FROM runtime AS runtime-test
# COPY .base/script/docker/runtime/smoke.sh /usr/local/lib/base/smoke.sh
# ARG RUNTIME_SMOKE_CMD='whoami && bash --version && bash /usr/local/lib/base/smoke.sh'

FROM devel-base AS example
COPY --chmod=0755 .base/script/docker/runtime/logging.sh /usr/local/lib/base/logging.sh
