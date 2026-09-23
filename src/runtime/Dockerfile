FROM alpine@sha256:fd791d74b68913cbb027c6546007b3f0d3bc45125f797758156952bc2d6daf40 AS toolchain

# build-base is a meta-package: the version pin froze nothing, because gcc,
# binutils and musl-dev still resolve against the branch index that --no-cache
# forces a re-fetch of. Keeping the toolchain in its own stage at least lets
# runtime:reproducible recompile without re-resolving it. Genuinely freezing the
# compiler needs a digest-pinned toolchain image published to a registry.
RUN apk add --no-cache build-base

FROM toolchain AS build

COPY janet.c janet.h shell.c /src/

RUN mkdir -p /out && \
    cc -std=c99 -O2 -DNDEBUG -DJANET_NO_DYNAMIC_MODULES \
    -I/src /src/janet.c /src/shell.c -static -pthread -ldl -lm \
    -o /out/janet && \
    strip /out/janet

FROM scratch

COPY --from=build /out/janet /janet
