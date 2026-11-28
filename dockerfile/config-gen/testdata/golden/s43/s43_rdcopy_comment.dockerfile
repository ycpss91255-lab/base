FROM busybox AS devel
RUN echo hi
# COPY --chmod=0755 .base/dist/script/docker/runtime/ /usr/local/lib/base/
