FROM busybox AS sys
ARG USER_NAME="user"
FROM sys AS devel
ARG USER="${USER_NAME}"
FROM devel AS t
ARG USER
USER "${USER}"
