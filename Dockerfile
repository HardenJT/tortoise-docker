# syntax=docker/dockerfile:1.7
# Tortoise WoW (Shyalya/tortoise-wow) — Ubuntu 22.04 build for GHCR + compose.
# Build-arg BUILD_PLAYERBOTS controls whether the playerbots module is compiled in.

ARG UBUNTU_VERSION=22.04

# -----------------------------------------------------------------------------
# Builder
# -----------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION} AS builder

ARG BUILD_PLAYERBOTS=ON
ARG USE_EXTRACTORS=OFF
ARG SOURCE_REPO=https://github.com/Shyalya/tortoise-wow.git
ARG SOURCE_REF=playerbots-integration-gh
ARG CMAKE_BUILD_TYPE=Release
ARG CMAKE_INSTALL_PREFIX=/opt/turtle
# Capped: -j$(nproc) on a 28-core host OOMs the 16GB WSL2 VM and crashes dockerd
ARG BUILD_JOBS=8

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        git \
        libace-dev \
        libboost-all-dev \
        default-libmysqlclient-dev \
        libssl-dev \
        zlib1g-dev \
        libbz2-dev \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN git clone --depth 1 --branch "${SOURCE_REF}" "${SOURCE_REPO}" tortoise-wow

WORKDIR /src/tortoise-wow

RUN cmake -B build \
        -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}" \
        -DCMAKE_INSTALL_PREFIX="${CMAKE_INSTALL_PREFIX}" \
        -DBUILD_PLAYERBOTS="${BUILD_PLAYERBOTS}" \
        -DUSE_EXTRACTORS="${USE_EXTRACTORS}" \
        -DALLOW_TURTLE_ADDONS=ON \
    && cmake --build build -j"${BUILD_JOBS}" \
    && cmake --install build

# Keep SQL needed for first-time DB init + AutoUpdate path.
RUN mkdir -p /opt/turtle/sql \
    && cp -a sql/create_databases.sql sql/base sql/database_updates /opt/turtle/sql/ \
    && if [ -d src/modules/PlayerBots/sql ]; then \
         mkdir -p /opt/turtle/sql/playerbots \
         && cp -a src/modules/PlayerBots/sql/. /opt/turtle/sql/playerbots/; \
       fi

# -----------------------------------------------------------------------------
# Runtime
# -----------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION} AS runtime

ARG BUILD_PLAYERBOTS=ON
ARG CMAKE_INSTALL_PREFIX=/opt/turtle

LABEL org.opencontainers.image.title="tortoise-docker" \
      org.opencontainers.image.description="Turtle WoW / Tortoise server (realmd + mangosd)" \
      org.opencontainers.image.source="https://github.com/Shyalya/tortoise-wow" \
      org.opencontainers.image.licenses="GPL-2.0"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    TURTLE_HOME=/opt/turtle \
    PLAYERBOTS_BUILT=${BUILD_PLAYERBOTS} \
    PATH=/opt/turtle/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        libace-7.0.6 \
        libboost-atomic1.74.0 \
        libboost-chrono1.74.0 \
        libboost-date-time1.74.0 \
        libboost-filesystem1.74.0 \
        libboost-iostreams1.74.0 \
        libboost-program-options1.74.0 \
        libboost-regex1.74.0 \
        libboost-serialization1.74.0 \
        libboost-system1.74.0 \
        libboost-thread1.74.0 \
        libmysqlclient21 \
        libssl3 \
        zlib1g \
        libbz2-1.0 \
        libreadline8 \
        libncurses6 \
        mariadb-client \
        tini \
        gosu \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 1000 turtle \
    && useradd --uid 1000 --gid turtle --home-dir /opt/turtle --shell /usr/sbin/nologin turtle

COPY --from=builder /opt/turtle /opt/turtle
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/init-db.sh /usr/local/bin/init-db.sh
COPY docker/render-config.sh /usr/local/bin/render-config.sh
COPY docker/repair-migrations.sh /usr/local/bin/repair-migrations.sh

RUN chmod +x /usr/local/bin/entrypoint.sh \
              /usr/local/bin/init-db.sh \
              /usr/local/bin/render-config.sh \
              /usr/local/bin/repair-migrations.sh \
    && mkdir -p /opt/turtle/data /opt/turtle/logs /opt/turtle/run /var/lib/turtle-init \
    && chown -R turtle:turtle /opt/turtle /var/lib/turtle-init

WORKDIR /opt/turtle/bin

EXPOSE 3724/tcp 8090/tcp

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["mangosd"]
