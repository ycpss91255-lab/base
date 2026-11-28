FROM busybox AS sys
COPY script/entrypoint.sh /entrypoint.sh
CMD ["sh"]
