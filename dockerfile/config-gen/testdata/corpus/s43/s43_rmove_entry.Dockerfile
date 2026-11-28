FROM busybox AS devel
COPY --chmod=0755 .base/script/docker/runtime/entrypoint.sh /entrypoint.sh
