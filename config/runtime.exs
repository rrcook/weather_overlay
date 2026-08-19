import Config

if dir = System.get_env("WEATHER_OUTPUT_DIR") do
  config :weather_overlay, output_dir: dir
end
