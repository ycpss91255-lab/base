FROM busybox AS devel
COPY --chmod=0755 .base/dist/script/docker/runtime/logging.sh .base/dist/script/docker/runtime/watchdog.sh /usr/local/lib/base/
