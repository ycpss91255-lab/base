FROM busybox AS sys
ARG USER_NAME="user"
RUN useradd "${USER_NAME}"
FROM sys AS devel-base
FROM devel-base AS devel
ARG USER="${USER_NAME}"
