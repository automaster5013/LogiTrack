FROM gcr.io/oss-fuzz-base/base-builder-jvm@sha256:5eaa9b0d62fe132cfd319061dffa85a7bb6a6795ff2cdd52872a4b3a2c816f4a

RUN apt-get update \
    && apt-get install -y --no-install-recommends maven \
    && rm -rf /var/lib/apt/lists/*

COPY . $SRC/logitrack
WORKDIR $SRC/logitrack
COPY .clusterfuzzlite/build.sh $SRC/build.sh
