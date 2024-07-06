# Copyright 2024, Ralph Richard Cook
#
# This file is part of Prodigy Reloaded.
#
# Prodigy Reloaded is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General
# Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# Prodigy Reloaded is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
# the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License along with Prodigy Reloaded. If not,
# see <https://www.gnu.org/licenses/>.

defmodule WeatherInit do
  use Application

  def start(_type, _args) do
    IO.puts("Initializing weather-based ets table.")
    :ets.new(:weather, [:public, :named_table])
    {:ok, proj} = Proj.from_epsg(2163)
    :ets.insert(:weather, {:equal_area, proj})

    WeatherMapper.make_weather_overlay()

    children = []
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
