FROM busybox:1.37.0-musl@sha256:fc6dddc4c44b1bfe37f41cae8e67d1693828e8f42a91862816d7953e2c9d3f23 AS health-tools

FROM otel/opentelemetry-collector-contrib:0.164.0@sha256:340c9ca6a36617084c6661bdc4f0fe92b7cda5a805d61673ec8db375fddc522b
COPY --from=health-tools /bin/busybox /busybox
HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=6 \
  CMD ["/busybox", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:13133/"]
