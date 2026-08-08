# syntax=docker/dockerfile:1
# Build stage for the content-batch image (see the Prodigy Reloaded content
# pipeline): produces a self-contained mix release of the weather overlay
# generator plus the PROJ 5 runtime its proj NIF links against.
#
# This image is not meant to run on its own - content-batch assembles it:
#   COPY --from=<this> /app/_build/prod/rel/weather_overlay ...
#   COPY --from=<this> /usr/local/lib/libproj.so.13* ...
#   COPY --from=<this> /usr/local/share/proj ...

FROM elixir:1.17.3-otp-27 AS build

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential curl ca-certificates git \
 && rm -rf /var/lib/apt/lists/*

# PROJ 5.2.0: the last release line with the PROJ.4 API (proj_api.h, removed
# in PROJ 8) that the proj NIF requires.  Installed to /usr/local, the layout
# the proj dep's Linux Makefile expects; its share/proj carries the epsg init
# file for +init=epsg:2163.
RUN curl -fsSL https://download.osgeo.org/proj/proj-5.2.0.tar.gz | tar xz -C /tmp \
 && cd /tmp/proj-5.2.0 \
 && ./configure --prefix=/usr/local >/dev/null \
 && make -j"$(nproc)" >/dev/null \
 && make install >/dev/null \
 && ldconfig \
 && rm -rf /tmp/proj-5.2.0

WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod
COPY lib lib
COPY priv priv
RUN mix deps.compile && mix compile && mix release --overwrite
