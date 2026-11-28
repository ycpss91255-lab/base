FROM busybox AS sys
COPY script/entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/usr/local/lib/base/entrypoint.sh"]
