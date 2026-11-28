FROM busybox AS sys
ARG \
    USER
FROM sys AS devel
ARG USER=\
    "${USER_NAME}"
FROM sys AS runtime
ARG USER_GROUP \
# a comment the parser drops
    USER="${USER_NAME}"
FROM sys AS test
ARG USER_GROUP USER
FROM sys AS lint
ARG USER_GROUP="g" USER="${USER_NAME}"
