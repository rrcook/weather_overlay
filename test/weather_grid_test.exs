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

defmodule WeatherGridTest do
  use ExUnit.Case

  test "grid covers CONUS uniformly" do
    grid = WeatherGrid.grid_lat_lons()
    assert length(grid) > 400

    {lats, lons} = Enum.unzip(grid)
    assert Enum.min(lats) >= 25.0 and Enum.max(lats) <= 49.0
    assert Enum.min(lons) >= -124.0 and Enum.max(lons) <= -68.0
  end

  test "parse_dwml extracts first maxt per point from a real response" do
    xml = File.read!("test/fixtures/ndfd_two_points.xml")
    points = WeatherGrid.parse_dwml(xml)

    assert [
             %{lat: 39.0, lon: -77.0, maxt: 87},
             %{lat: 35.0, lon: -106.0, maxt: 98}
           ] = Enum.sort_by(points, & &1.lon, :desc)
  end

  test "parse_dwml tolerates garbage" do
    assert WeatherGrid.parse_dwml("not xml at all") == []
    assert WeatherGrid.parse_dwml("<data></data>") == []
  end
  test "parse_dwml averages the first hours of cloud cover when present" do
    xml = File.read!("test/fixtures/ndfd_two_points_sky.xml")
    points = WeatherGrid.parse_dwml(xml)

    assert length(points) == 2
    assert Enum.all?(points, &is_number(&1.sky))
    assert Enum.all?(points, &(&1.sky >= 0 and &1.sky <= 100))
  end

  test "parse_dwml yields sky: nil when the response has no cloud cover" do
    xml = File.read!("test/fixtures/ndfd_two_points.xml")
    points = WeatherGrid.parse_dwml(xml)
    assert Enum.all?(points, &is_nil(&1.sky))
  end
end
