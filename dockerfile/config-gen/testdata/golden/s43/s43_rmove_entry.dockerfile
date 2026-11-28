FROM busybox AS devel
COPY --chmod=0755 .base/dist/dockerfile/entrypoint.sh /entrypoint.sh
