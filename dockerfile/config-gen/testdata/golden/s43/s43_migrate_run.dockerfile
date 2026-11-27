FROM devel AS lint
COPY .base/dist/script/docker/lib /lint/lib
RUN ls .base/dist/script/docker/wrapper
