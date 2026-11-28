FROM busybox AS sys
ARG USER=initial
RUN echo sys
FROM sys AS devel
ARG USER
RUN echo devel
