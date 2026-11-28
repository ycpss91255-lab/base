FROM busybox AS lint
COPY .base/dist/script/docker/lib /lint/lib
COPY .base/dist/script/docker/wrapper /lint/wrapper
