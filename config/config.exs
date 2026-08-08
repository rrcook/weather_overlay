import Config

# Set false to drop the isobar layer (and its Open-Meteo dependency).
config :weather_overlay, isobars: true

# Where WO.NAP / the wrapped object / the fetch cache land; overridden at
# runtime by WEATHER_OUTPUT_DIR (see config/runtime.exs).
config :weather_overlay, output_dir: "output"
