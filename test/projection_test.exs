# Copyright 2026, Ralph Richard Cook
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

defmodule WeatherOverlay.ProjectionTest do
  use ExUnit.Case, async: true

  alias WeatherOverlay.Projection

  # Reference {easting, northing} produced by libproj's pj_transform WGS84 ->
  # EPSG:2163 (the former :proj C NIF). These pin the pure-Elixir spherical
  # LAEA formula so it can never silently drift from PROJ.
  @reference [
    {{45.0, -100.0}, {0.0, 0.0}},
    {{40.0, -100.0}, {0.0, -555_797.9721}},
    {{45.0, -90.0}, {783_770.5512, 48_487.0460}},
    {{30.0, -120.0}, {-1_921_494.4557, -1_439_433.3209}},
    {{49.0, -95.0}, {364_672.4458, 456_144.3128}},
    {{25.0, -80.0}, {2_025_599.9675, -1_982_446.4140}},
    {{48.0, -122.0}, {-1_611_455.8861, 557_949.8951}}
  ]

  # libproj agreement is ~5e-5 m; 1e-3 m (1 mm) is a comfortable, meaningful bound.
  @tolerance_m 1.0e-3

  describe "from_lat_lng!/1 (EPSG:2163 spherical LAEA)" do
    for {{lat, lng} = coords, {expected_x, expected_y}} <- @reference do
      test "#{lat}, #{lng} matches libproj" do
        {x, y} = Projection.from_lat_lng!(unquote(Macro.escape(coords)))
        assert_in_delta x, unquote(expected_x), @tolerance_m
        assert_in_delta y, unquote(expected_y), @tolerance_m
      end
    end

    test "the projection center maps to the origin" do
      assert {x, y} = Projection.from_lat_lng!({45.0, -100.0})
      assert_in_delta x, 0.0, @tolerance_m
      assert_in_delta y, 0.0, @tolerance_m
    end
  end
end
