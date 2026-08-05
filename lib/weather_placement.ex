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

defmodule WeatherPlacement do
  @moduledoc """
  Data-driven callout placement for the weather overlay.

  The original Prodigy maps were sparse and readable: 2-4 "H"/"L" pressure
  marks (rarely 5), and callouts that never sat on top of each other.  The
  WPC feature collection carries every analyzed center (often 14+ inside the
  map), so this module thins same-type pressure centers into representative
  "communities" and resolves callout bounding-box collisions.

  All coordinates here are GCU pixels (0-255, y up).  Callers convert to the
  0..1 fractions the NAPLPS drawing functions take.  Everything is pure and
  deterministic - no randomness - so a given day's data always produces the
  same map.
  """

  # The region of the screen the base map occupies (GCU px).
  @map_min_x 36
  @map_max_x 253
  @map_min_y 53
  @map_max_y 182

  # Same-type centers closer than this merge into one community.
  @merge_threshold 35
  # Keep at most this many communities per pressure type ...
  @per_type_cap 2
  # ... plus a 3rd if it sits well away from the chosen ones.
  @third_group_min_dist 60
  # Hard cap across both types (originals: 2-4, rarely 5).
  @total_cap 5

  # Offsets tried (in order) when a callout's box collides: stay put, then a
  # ring at 12 px, then 24 px.
  @offsets [{0, 0}] ++
             (for r <- [12, 24], {dx, dy} <- [{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, 1}, {1, -1}, {-1, -1}] do
                {dx * r, dy * r}
              end)

  @doc "The map region every layer places/clips against (GCU px)."
  def map_bounds, do: {@map_min_x, @map_max_x, @map_min_y, @map_max_y}

  @doc """
  Thin pressure centers to the sparse look of the originals.

  `centers` is a list of `{:high | :low, {x, y}}` in GCU px.  Same-type
  centers are merged into communities by single-linkage clustering
  (threshold #{@merge_threshold} px); each community is represented by its
  centroid.  Up to #{@per_type_cap} communities per type are kept (largest
  first), plus a 3rd if it lies at least #{@third_group_min_dist} px from
  those already chosen; #{@total_cap} total, interleaved by type so neither
  type is starved.
  """
  def thin_pressures(centers) do
    per_type =
      for type <- [:high, :low] do
        points = for {^type, xy} <- centers, do: xy

        points
        |> cluster(@merge_threshold)
        |> Enum.sort_by(&{-length(&1), &1})
        |> choose_groups()
        |> Enum.map(fn group -> {type, centroid(group)} end)
      end

    per_type
    |> interleave()
    |> Enum.take(@total_cap)
  end

  @doc """
  Resolve callout collisions by greedy placement in priority order.

  Each callout is a map with `:x`/`:y` (box lower-left, GCU px), `:w`/`:h`,
  and `:priority` (lower number = more important; placed first).  A callout
  whose box overlaps an already-placed box, or leaves the map region, is
  nudged through a small ring of offsets; if nothing fits it is dropped.
  Returns the placed callouts in input order (minus any dropped).
  """
  def resolve_collisions(callouts) do
    callouts
    |> Enum.sort_by(& &1.priority)
    |> Enum.reduce([], fn callout, placed ->
      case fit(callout, placed) do
        {:ok, positioned} -> [positioned | placed]
        :drop -> placed
      end
    end)
    |> Enum.reverse()
  end

  # Communities smaller than this share are noise, not weather (a 650-point
  # grid gives ~43 points per k=15 cluster if spread evenly).
  @min_community_points 6
  # A community whose modal decade covers less than this share of its points
  # is straddling a temperature boundary and gets split once.
  @purity_threshold 0.6
  @purity_split_min_points 8

  @doc """
  Temperature communities: k-means over the grid points' map coordinates,
  each cluster labeled with its modal temperature decade.

  `points` is `[%{x, y, temp}]` in GCU px; `k` the community budget (the
  observed originals carry 12-15 temp callouts).  Clusters whose modal
  decade covers less than #{trunc(@purity_threshold * 100)}% of their points
  straddle a real temperature boundary and are split once.  Tiny clusters
  are dropped.  Deterministic: farthest-point seeding, no randomness.

  Returns `[%{x, y, decade, count}]` (x/y = community centroid).
  """
  def temp_communities(points, k) do
    points
    |> kmeans(k)
    |> Enum.flat_map(fn cluster ->
      if purity(cluster) < @purity_threshold and length(cluster) >= @purity_split_min_points do
        kmeans(cluster, 2)
      else
        [cluster]
      end
    end)
    |> Enum.reject(&(length(&1) < @min_community_points))
    |> Enum.map(fn cluster ->
      {cx, cy} = centroid(Enum.map(cluster, &{&1.x, &1.y}))
      %{x: cx, y: cy, decade: modal_decade(cluster), count: length(cluster)}
    end)
  end

  @doc """
  The original maps sometimes wrote a word where a number would repeat: five
  "80s" across a region and the interior ones just say "warm".  For each
  decade with at least 3 communities, the most interior one (smallest mean
  distance to its same-decade peers) trades its number for the adjective.

  Takes and returns the `temp_communities/2` shape, adding `:label` and
  `:kind` (`:temp` | `:word`).
  """
  def label_temp_communities(communities) do
    word_positions =
      communities
      |> Enum.group_by(& &1.decade)
      |> Enum.filter(fn {_decade, group} -> length(group) >= 3 end)
      |> Enum.map(fn {_decade, group} ->
        group
        |> Enum.min_by(fn c ->
          peers = List.delete(group, c)
          Enum.sum(Enum.map(peers, &distance({c.x, c.y}, {&1.x, &1.y}))) / length(peers)
        end)
        |> then(&{&1.x, &1.y})
      end)
      |> MapSet.new()

    Enum.map(communities, fn c ->
      if MapSet.member?(word_positions, {c.x, c.y}) do
        Map.merge(c, %{kind: :word, label: adjective(c.decade)})
      else
        Map.merge(c, %{kind: :temp, label: "#{c.decade}s"})
      end
    end)
  end

  @doc "Decade -> condition word, per the original maps' vocabulary."
  def adjective(decade) when decade <= 30, do: "cold"
  def adjective(decade) when decade in [40, 50], do: "cool"
  def adjective(60), do: "mild"
  def adjective(70), do: "nice"
  def adjective(80), do: "warm"
  def adjective(_), do: "hot"

  @doc """
  Deterministic k-means (Lloyd's) over maps with `:x`/`:y`.  Seeding is
  farthest-point (start nearest the global centroid, then repeatedly add the
  point farthest from every seed) - fully deterministic for a given input
  order, no RNG.  Returns clusters as lists of the input maps.
  """
  def kmeans(points, k) when length(points) <= k, do: Enum.map(points, &[&1])

  def kmeans(points, k) do
    coords = Enum.map(points, &{&1.x, &1.y})
    centroids = seed_centroids(coords, k)
    lloyd(points, coords, centroids, 25)
  end

  defp seed_centroids(coords, k) do
    global = centroid(coords)
    first = Enum.min_by(coords, &distance(&1, global))

    Enum.reduce(2..k, [first], fn _, seeds ->
      next = Enum.max_by(coords, fn p -> seeds |> Enum.map(&distance(p, &1)) |> Enum.min() end)
      [next | seeds]
    end)
    |> Enum.reverse()
  end

  defp lloyd(points, coords, centroids, iterations_left) do
    assignments = Enum.map(coords, &nearest_index(&1, centroids))

    clusters =
      Enum.zip(assignments, Enum.zip(points, coords))
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    new_centroids =
      centroids
      |> Enum.with_index()
      |> Enum.map(fn {old, i} ->
        case clusters[i] do
          nil -> old
          members -> members |> Enum.map(&elem(&1, 1)) |> centroid()
        end
      end)

    if new_centroids == centroids or iterations_left == 0 do
      clusters
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {_i, members} -> Enum.map(members, &elem(&1, 0)) end)
    else
      lloyd(points, coords, new_centroids, iterations_left - 1)
    end
  end

  defp nearest_index(point, centroids) do
    centroids
    |> Enum.with_index()
    |> Enum.min_by(fn {c, _i} -> distance(point, c) end)
    |> elem(1)
  end

  defp decade(temp) when temp < 0, do: -(decade(-temp))
  defp decade(temp), do: trunc(temp) - rem(trunc(temp), 10)

  defp modal_decade(cluster) do
    cluster
    |> Enum.frequencies_by(&decade(&1.temp))
    |> Enum.max_by(fn {decade, count} -> {count, decade} end)
    |> elem(0)
  end

  defp purity(cluster) do
    {_decade, count} =
      cluster
      |> Enum.frequencies_by(&decade(&1.temp))
      |> Enum.max_by(fn {decade, count} -> {count, decade} end)

    count / length(cluster)
  end

  # -- clustering -----------------------------------------------------

  # Single-linkage agglomerative clustering: merge any two groups whose
  # closest members are within `threshold`.  n is small (<= ~15), so the
  # simple O(n^3) repeated scan is fine.
  defp cluster(points, threshold) do
    groups = Enum.map(points, &[&1])
    merge_pass(groups, threshold)
  end

  defp merge_pass(groups, threshold) do
    pair =
      for {a, i} <- Enum.with_index(groups),
          {b, j} <- Enum.with_index(groups),
          i < j,
          linked?(a, b, threshold) do
        {i, j}
      end
      |> List.first()

    case pair do
      nil ->
        groups

      {i, j} ->
        merged = Enum.at(groups, i) ++ Enum.at(groups, j)

        groups
        |> List.delete_at(j)
        |> List.delete_at(i)
        |> then(&[merged | &1])
        |> merge_pass(threshold)
    end
  end

  defp linked?(a, b, threshold) do
    Enum.any?(a, fn p -> Enum.any?(b, fn q -> distance(p, q) <= threshold end) end)
  end

  defp distance({x1, y1}, {x2, y2}) do
    :math.sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2))
  end

  defp centroid(points) do
    n = length(points)
    {xs, ys} = Enum.unzip(points)
    {Enum.sum(xs) / n, Enum.sum(ys) / n}
  end

  # Keep the largest groups up to the per-type cap, plus one more if its
  # centroid is far from every centroid already chosen.
  defp choose_groups(groups) do
    {keep, rest} = Enum.split(groups, @per_type_cap)

    extra =
      Enum.find(rest, fn group ->
        c = centroid(group)
        Enum.all?(keep, fn kept -> distance(c, centroid(kept)) >= @third_group_min_dist end)
      end)

    if extra, do: keep ++ [extra], else: keep
  end

  # [[a1, a2], [b1, b2, b3]] -> [a1, b1, a2, b2, b3] - fair total-cap cuts.
  defp interleave(lists) do
    do_interleave(lists, [])
  end

  defp do_interleave(lists, acc) do
    case Enum.filter(lists, &(&1 != [])) do
      [] -> Enum.reverse(acc)
      nonempty -> do_interleave(Enum.map(nonempty, &tl/1), Enum.reverse(Enum.map(nonempty, &hd/1)) ++ acc)
    end
  end

  # -- collision ------------------------------------------------------

  defp fit(callout, placed) do
    @offsets
    |> Enum.find(fn {dx, dy} ->
      candidate = %{callout | x: callout.x + dx, y: callout.y + dy}
      in_bounds?(candidate) and not Enum.any?(placed, &overlap?(candidate, &1))
    end)
    |> case do
      nil -> :drop
      {dx, dy} -> {:ok, %{callout | x: callout.x + dx, y: callout.y + dy}}
    end
  end

  defp in_bounds?(%{x: x, y: y, w: w, h: h}) do
    x >= @map_min_x and x + w <= @map_max_x and y >= @map_min_y and y + h <= @map_max_y
  end

  defp overlap?(a, b) do
    a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
  end
end
