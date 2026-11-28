FROM busybox AS lint
COPY *.sh /lint/
RUN shellcheck -S warning /lint/*.sh
