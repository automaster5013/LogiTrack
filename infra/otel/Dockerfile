FROM busybox:1.37.0-musl AS health-tools

FROM otel/opentelemetry-collector-contrib:0.161.0
COPY --from=health-tools /bin/busybox /busybox
