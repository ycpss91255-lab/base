FROM devel AS devel
COPY .base/dist/script/docker/runtime/logging.sh \
     /usr/local/lib/base/logging.sh
