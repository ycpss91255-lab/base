FROM busybox AS runtime
COPY --chmod=0755 .base/dist/script/docker/runtime/ /usr/local/lib/base/

FROM busybox AS devel
COPY --chmod=0755 .base/dist/script/docker/runtime/ /usr/local/lib/base/

FROM devel AS devel-test
RUN echo hi
