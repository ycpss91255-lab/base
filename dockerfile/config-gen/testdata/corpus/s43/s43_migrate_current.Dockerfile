FROM devel AS lint
COPY .base/dist/script/docker/lib /lint/lib
RUN echo lint
