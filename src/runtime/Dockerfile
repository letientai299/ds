FROM alpine@sha256:fd791d74b68913cbb027c6546007b3f0d3bc45125f797758156952bc2d6daf40 AS build

RUN apk add --no-cache build-base=0.5-r3

COPY janet.c janet.h shell.c /src/

RUN mkdir -p /out && \
    cc -std=c99 -O2 -DNDEBUG -DJANET_NO_DYNAMIC_MODULES \
    -I/src /src/janet.c /src/shell.c -static -pthread -ldl -lm \
    -o /out/janet && \
    strip /out/janet

FROM scratch

COPY --from=build /out/janet /janet
