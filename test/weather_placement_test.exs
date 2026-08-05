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

defmodule WeatherPlacementTest do
  use ExUnit.Case

  # ---- thin_pressures ------------------------------------------------

  test "nearby same-type centers merge into one community at their centroid" do
    thinned = WeatherPlacement.thin_pressures([{:low, {100, 100}}, {:low, {120, 100}}])
    assert [{:low, {110.0, 100.0}}] = thinned
  end

  test "distant same-type centers stay separate (up to the per-type cap)" do
    thinned = WeatherPlacement.thin_pressures([{:high, {60, 100}}, {:high, {200, 100}}])
    assert length(thinned) == 2
  end

  test "a crowded field is capped at 2 per type, largest communities first" do
    lows = [
      # community of 3 around (100, 100)
      {:low, {95, 100}},
      {:low, {105, 100}},
      {:low, {100, 110}},
      # community of 2 around (200, 80)
      {:low, {195, 80}},
      {:low, {205, 80}},
      # lone low nearby the first community's chosen area (not far enough for a 3rd)
      {:low, {140, 120}}
    ]

    thinned = WeatherPlacement.thin_pressures(lows)
    assert length(thinned) == 2
    assert Enum.all?(thinned, fn {type, _} -> type == :low end)
    # largest first: the 3-member community's centroid
    assert [{:low, {100.0, _}} | _] = thinned
  end

  test "a well-separated 3rd community of a type is kept" do
    lows = [
      {:low, {60, 80}},
      {:low, {150, 80}},
      {:low, {240, 170}}
    ]

    thinned = WeatherPlacement.thin_pressures(lows)
    assert length(thinned) == 3
  end

  test "total is capped at 5 with both types represented" do
    centers =
      for x <- [50, 130, 240], type <- [:high, :low] do
        # separate the types vertically so nothing cross-merges
        {type, {x, if(type == :high, do: 70, else: 160)}}
      end

    thinned = WeatherPlacement.thin_pressures(centers)
    assert length(thinned) == 5
    types = Enum.map(thinned, &elem(&1, 0))
    assert :high in types and :low in types
  end

  test "today's real shape: 14 centers thin to 2-4 (cap 5)" do
    # Approximation of the 2026-08-05 WPC feed after the continental filter.
    centers = [
      {:high, {112, 92}},
      {:high, {223, 68}},
      {:high, {129, 113}},
      {:high, {186, 130}},
      {:high, {121, 133}},
      {:low, {162, 103}},
      {:low, {192, 127}},
      {:low, {215, 139}},
      {:low, {172, 111}},
      {:low, {60, 119}},
      {:low, {101, 82}},
      {:low, {77, 152}},
      {:low, {104, 111}},
      {:low, {87, 101}}
    ]

    thinned = WeatherPlacement.thin_pressures(centers)
    assert length(thinned) >= 2 and length(thinned) <= 5
  end

  test "thinning is deterministic" do
    centers = [{:low, {100, 100}}, {:low, {120, 100}}, {:high, {200, 150}}]
    assert WeatherPlacement.thin_pressures(centers) == WeatherPlacement.thin_pressures(centers)
  end

  # ---- resolve_collisions --------------------------------------------

  defp callout(x, y, priority \\ 0), do: %{kind: :test, x: x, y: y, w: 6, h: 10, priority: priority}

  defp boxes_overlap?(a, b) do
    a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
  end

  test "non-overlapping callouts are unchanged" do
    callouts = [callout(50, 100), callout(150, 100)]
    assert WeatherPlacement.resolve_collisions(callouts) == callouts
  end

  test "an overlapping callout is nudged so no boxes overlap" do
    placed = WeatherPlacement.resolve_collisions([callout(100, 100, 0), callout(102, 102, 1)])
    assert length(placed) == 2
    [a, b] = placed
    refute boxes_overlap?(a, b)
  end

  test "placed callouts stay inside the map region" do
    # Anchored at the map edge: must be nudged inward, not out of bounds.
    placed = WeatherPlacement.resolve_collisions([callout(36, 53), callout(37, 54, 1)])

    Enum.each(placed, fn c ->
      assert c.x >= 36 and c.x + c.w <= 253
      assert c.y >= 53 and c.y + c.h <= 182
    end)
  end

  test "a callout with nowhere to go is dropped, higher priority survives" do
    # Ring a target with enough boxes that every offset is taken.
    blockers =
      for {dx, dy} <- [{0, 0}, {12, 0}, {-12, 0}, {0, 12}, {0, -12}, {12, 12}, {-12, 12}, {12, -12}, {-12, -12}, {24, 0}, {-24, 0}, {0, 24}, {0, -24}, {24, 24}, {-24, 24}, {24, -24}, {-24, -24}] do
        callout(120 + dx, 120 + dy, 0)
      end

    placed = WeatherPlacement.resolve_collisions(blockers ++ [callout(121, 121, 9)])
    refute Enum.any?(placed, &(&1.priority == 9))
  end
end
