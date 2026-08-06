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

defmodule WeatherWindTest do
  use ExUnit.Case

  # build_wind_callouts is pure over GCU points - a windy blob yields one
  # centered word callout; calm points yield nothing.
  test "a windy region becomes one word callout at its centroid" do
    windy = for i <- 0..8, do: %{x: 100 + rem(i, 3) * 6, y: 100 + div(i, 3) * 6, wind: 27.0, gust: nil}
    calm = for i <- 0..8, do: %{x: 200 + rem(i, 3) * 6, y: 150 + div(i, 3) * 6, wind: 4.0, gust: nil}

    callouts = WeatherMapper.build_wind_callouts(windy ++ calm)
    assert [%{kind: :wind, label: "windy", priority: 3}] = callouts
  end

  test "parse_dwml extracts wind and gust in mph from the full fixture" do
    xml = File.read!("test/fixtures/ndfd_two_points_full.xml")
    points = WeatherGrid.parse_dwml(xml)

    assert length(points) == 2
    assert Enum.all?(points, &(is_number(&1.wind) and is_number(&1.gust)))
    assert Enum.all?(points, &(&1.gust >= &1.wind))
  end

  test "parse_dwml yields nil wind when the response has no wind elements" do
    xml = File.read!("test/fixtures/ndfd_two_points.xml")
    points = WeatherGrid.parse_dwml(xml)
    assert Enum.all?(points, &(is_nil(&1.wind) and is_nil(&1.gust)))
  end
end
