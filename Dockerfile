# syntax=docker/dockerfile:1
# Build stage for the content-batch image (see the Prodigy Reloaded content
# pipeline): produces a self-contained mix release of the weather overlay
# generator.
#
# This image is not meant to run on its own - content-batch assembles it:
#   COPY --from=<this> /app/_build/prod/rel/weather_overlay ...

FROM elixir:1.17.3-otp-27 AS build

WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod
COPY lib lib
COPY priv priv
RUN mix deps.compile && mix compile && mix release --overwrite
