ARG BASE_IMAGE
# hadolint ignore=DL3006
FROM ${BASE_IMAGE} AS runtime
COPY --chmod=0755 .base/dist/script/docker/runtime/ /usr/local/lib/base/

# hadolint ignore=DL3006
FROM ${BASE_IMAGE} AS devel
COPY --chmod=0755 .base/dist/script/docker/runtime/ /usr/local/lib/base/

FROM runtime AS runtime-test
# COPY .base/dist/test/bats/smoke/smoke.sh /usr/local/lib/base/smoke.sh
# ARG RUNTIME_SMOKE_CMD='whoami && bash --version && bash /usr/local/lib/base/smoke.sh'

FROM devel-base AS example
COPY --chmod=0755 .base/dist/script/docker/runtime/ /usr/local/lib/base/
