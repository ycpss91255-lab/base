FROM busybox AS lint
COPY .base/dist/script/docker/lib /lint/lib

FROM busybox AS devel
COPY --chmod=0755 .base/dist/config "${CONFIG_DIR}"
