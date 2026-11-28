FROM busybox AS sys
ARG USER_NAME=dev
FROM sys AS devel
ARG USER="${USER_NAME}"
RUN echo devel
FROM devel AS test
ARG USER="${USER_NAME}"
RUN echo test
