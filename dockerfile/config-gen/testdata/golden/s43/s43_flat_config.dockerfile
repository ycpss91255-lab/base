FROM busybox AS devel
COPY --chown="${USER}":"${GROUP}" --chmod=0755 .base/dist/config "${CONFIG_DIR}"
