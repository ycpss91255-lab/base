FROM devel AS lint
COPY .base/downstream/script/docker/lib /lint/lib
RUN ls .base/downstream/script/docker/wrapper
