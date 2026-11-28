ARG USER_NAME="user"
FROM busybox AS sys
ARG USER
FROM sys AS devel
ARG USER="${USER_NAME}"
