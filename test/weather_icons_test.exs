# Copyright 2026, Phillip Heller and Ralph Richard Cook
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

defmodule WeatherIconsTest do
  use ExUnit.Case

  test "sky quantization boundaries" do
    assert WeatherPlacement.sky_category(0) == :sunny
    assert WeatherPlacement.sky_category(30) == :sunny
    assert WeatherPlacement.sky_category(31) == :partly
    assert WeatherPlacement.sky_category(69) == :partly
    assert WeatherPlacement.sky_category(70) == :cloudy
    assert WeatherPlacement.sky_category(100) == :cloudy
  end

  test "sky category regions produce icon callouts through the community pipeline" do
    cloudy = for i <- 0..23, do: %{x: 60 + rem(i, 6) * 8, y: 90 + div(i, 6) * 8, temp: 70, sky: 85}
    sunny = for i <- 0..23, do: %{x: 180 + rem(i, 6) * 8, y: 130 + div(i, 6) * 8, temp: 90, sky: 5}
    no_sky = [%{x: 120, y: 120, temp: 60, sky: nil}]

    callouts = WeatherMapper.build_icon_callouts(cloudy ++ sunny ++ no_sky)
    kinds = Enum.map(callouts, & &1.kind)

    assert {:icon, :cloudy} in kinds
    assert {:icon, :sunny} in kinds
    assert Enum.all?(callouts, &(&1.priority == 2 and &1.w == 24 and &1.h == 16))
  end
end
