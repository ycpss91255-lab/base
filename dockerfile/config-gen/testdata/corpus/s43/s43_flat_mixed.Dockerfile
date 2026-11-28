FROM busybox AS lint
COPY .base/script/docker/lib /lint/lib

FROM busybox AS devel
COPY --chmod=0755 .base/config "${CONFIG_DIR}"
