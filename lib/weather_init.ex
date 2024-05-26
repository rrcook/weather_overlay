defmodule WeatherInit do
  use Application

  def start(_type, _args) do
    IO.puts("Initializing weather-based ets table.")
    :ets.new(:weather, [:public, :named_table])
    {:ok, proj} = Proj.from_epsg(2163)
    :ets.insert(:weather, {:equal_area, proj})

    children = []
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
