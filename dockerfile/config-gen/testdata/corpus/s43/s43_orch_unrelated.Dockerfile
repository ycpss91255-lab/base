# tool-pin: ignore -- fixture bytes for the entrypoint_orchestrator migration, never built (base#2077)
FROM ubuntu:24.04 AS devel
ARG ENTRYPOINT_FILE="script/entrypoint.sh"
COPY --chmod=0755 "./${ENTRYPOINT_FILE}" "/entrypoint.sh"
COPY --chmod=0755 .base/dist/script/docker/runtime/ /usr/local/lib/base/
ENTRYPOINT ["/usr/local/lib/base/entrypoint.sh"]
CMD ["bash"]
ENTRYPOINT ["/ros_entrypoint.sh"]
