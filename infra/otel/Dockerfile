FROM busybox:1.38.0-musl@sha256:ea2b9914a16a4ac1981994af97b318f7c7d4db76b580c56177f08bf76f4a0be8 AS health-tools

FROM otel/opentelemetry-collector-contrib:0.161.0@sha256:fd328de2552466ad78385e1b1289c3f2402b1c45f265b252aab1955b42845ac1
COPY --from=health-tools /bin/busybox /busybox
HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=6 \
  CMD ["/busybox", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:13133/"]
