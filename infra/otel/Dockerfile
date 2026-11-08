FROM busybox:1.38.0-musl@sha256:80e38f9a1b39188b8bdb28879178edb322a4402b081a9aedda1924609decd6f6 AS health-tools

FROM otel/opentelemetry-collector-contrib:0.164.0-386@sha256:40392928d2b988b77e7525dbac33e5e3d9bedb40b9ff8c1f9119d92ca3a8a1c3
COPY --from=health-tools /bin/busybox /busybox
HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=6 \
  CMD ["/busybox", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:13133/"]
