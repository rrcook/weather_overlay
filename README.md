# Weather Overlay

**Prodigy-style weather map in NAPLPS**

An Elixir application that will write a "weather overlay" that changes daily over
a map of the continental United States. 
The application produces a NAPLPS graphics file used in Prodigy, overlaid on top 
of a separate NAPLPS graphic.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `naplps_writer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:weather_overlay, "~> 0.1.0"}
  ]
end
```

A tempoary repository to develop a Prodigy-style weather map overlay using NAPLPS.
Weather will be read in from a site or API and converted to NAPLPS that will fit
on the Prodigy weather map page.

When development is completed this project will be put into [Prodigy Reloaded](https://github.com/prodigyreloaded)

## Architecture (callout-placement branch)

The overlay is generated in layers, bottom to top:

1. **Isobars** (`WeatherIsobars`) - MSLP contours at 4 hPa, marching squares
   over a smoothed grid, clipped to land, thin blue lines drawn first.
2. **Precipitation polygons + legends** - WPC feature collection (rain black,
   snow white), as before.
3. **Pressure marks** - WPC's analyzed H/L centers thinned to the originals'
   2-4 marks (single-linkage communities, `WeatherPlacement.thin_pressures`),
   drawn white at 2x text size.
4. **Temperatures** - a uniform 1.5-degree NDFD forecast grid
   (`WeatherGrid`), k-means communities labeled by modal decade
   (`WeatherPlacement.temp_communities`), repeated decades collapsed into
   condition words ("warm"), yellow text.
5. **Sky icons** - the same grid's cloud cover quantized to sunny / partly /
   cloudy communities; t-storm icons at WPC thunderstorm polygon centroids;
   drawn with the WeatherObjects icon functions.
6. **Wind words** - "breezy" / "windy" / "gusty" communities from the grid's
   wind fields, white text.

All callouts go through one deterministic collision pass
(`WeatherPlacement.resolve_collisions`; priority: pressures > temps > icons >
wind words) - no randomness anywhere, so a given day's data always produces
the same map.

### Data sources

- NDFD multi-point XML (graphical.weather.gov): max temperature, sky cover,
  wind, gusts - one batched fetch, cached per day under `output/cache/`.
- WPC National Forecast Chart feature collection: precipitation polygons,
  analyzed pressure centers, thunderstorm areas.
- Open-Meteo forecast API: mean-sea-level pressure for the isobars only
  (NDFD carries no pressure field; this is the one non-NOAA source - set
  `config :weather_overlay, isobars: false` to turn the layer off and
  drop the dependency).

### Building / running

- Erlang/Elixir pinned in `.tool-versions` (asdf).
- The `proj` dependency needs a PROJ install that still provides the PROJ.4
  API (`proj_api.h`, removed in PROJ 8): build PROJ 5.x into a prefix and
  compile the NIF against it, then run with `PROJ_LIB=<prefix>/share/proj`.
- Generate: `mix run -e "WeatherOverlay.main([])"` -> `output/WO.NAP` (raw
  overlay) and `output/WM00A000.B_1_8_1` (wrapped Page Element Object).
