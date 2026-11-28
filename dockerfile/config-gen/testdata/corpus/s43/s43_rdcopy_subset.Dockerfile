FROM busybox AS devel
COPY --chmod=0755 .base/script/docker/runtime/watchdog.sh /usr/local/lib/base/watchdog.sh
COPY --chmod=0755 .base/script/docker/runtime/logging.sh /usr/local/lib/base/logging.sh
