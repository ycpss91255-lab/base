FROM busybox AS sys
ARG USER="initial"
FROM busybox AS other
ARG USER_NAME="user"
FROM sys AS devel
ARG USER="${USER_NAME}"
