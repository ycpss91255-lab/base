FROM busybox AS devel
COPY --chmod=0755 .base/dist/script/docker/runtime/logging.sh /opt/base/logging.sh
