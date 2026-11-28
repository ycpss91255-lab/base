FROM busybox AS sys
RUN echo one \
    two
ARG USER \
    GROUP
FROM sys AS devel
ARG USER="${USER_NAME}" \
    GROUP="${USER_GROUP}"
