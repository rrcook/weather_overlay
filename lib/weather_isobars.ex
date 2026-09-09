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

defmodule WeatherIsobars do
  @moduledoc """
  Isobars for the weather map: mean-sea-level pressure contours, drawn as thin
  curves under the callouts - both demo-disk originals (1988 and 1990) show
  them.

  NDFD carries no pressure field, so MSLP comes from the Open-Meteo forecast
  API (the one non-NOAA source in the pipeline) on the same 1.5-degree grid as
  WeatherGrid, cached per day.  Contours are traced with marching squares at
  4 hPa intervals in lat/lon space, mapped through the same equal-area
  projection as everything else, chained into polylines, and clipped to the
  map region.

  Self-contained by design: the only caller is one pipe in
  make_weather_overlay, and the layer is gated by
  `config :weather_overlay, isobars: false` - flip it off to drop the
  curves and the Open-Meteo dependency with them.
  """
  import NaplpsWriter
  use NaplpsConstants

  require Logger

  @endpoint "https://api.open-meteo.com/v1/forecast"
  @batch_size 100

  # Standard synoptic-chart spacing.
  @interval_hpa 4


  @doc """
  Fetch (cached), contour, and append the isobar curves to the buffer.
  On any fetch/parse failure the buffer passes through unchanged - the map
  simply has no isobars that day.
  """
  def append(buffer, cache_dir, date \\ Date.utc_today()) do
    if Application.get_env(:weather_overlay, :isobars, true) do
      do_append(buffer, cache_dir, date)
    else
      buffer
    end
  end

  defp do_append(buffer, cache_dir, date) do
    case polylines(cache_dir, date) do
      [] ->
        buffer

      lines ->
        buffer
        # Isobars are the first layer in the object, so this is the stream's
        # preamble: gcu_init emits the minimal logical pel (the domain the
        # decompiles show as "DOMAIN 200 192 192 201") *and* the TEXTURE +
        # shift-in that the domain alone leaves undefined - without them the
        # isobar lines inherit whatever line texture the previously displayed
        # object left in the decoder.
        |> gcu_init()
        |> select_color(@color_blue)
        |> then(fn buf -> Enum.reduce(lines, buf, &draw_polyline(&2, &1)) end)
        |> draw(@cmd_set_point_rel, [])
    end
  end

  @doc "Contoured isobar polylines in GCU px, [[{x, y}, ...], ...]."
  def polylines(cache_dir, date \\ Date.utc_today()) do
    case pressure_grid(cache_dir, date) do
      nil ->
        []

      {lats, lons, values} ->
        # MSL reduction over high terrain is noisy at grid scale; real charts
        # smooth the field before contouring (one 3x3 pass - two flattens a
        # weak summer field into nothing).
        values = smooth(values, lats, lons)
        land = land_mask(cache_dir, date)

        levels(values)
        |> Enum.flat_map(fn level -> contour(lats, lons, values, level) end)
        |> Enum.flat_map(&clip_to_land(&1, land))
        |> Enum.map(&to_gcu_px/1)
        |> Enum.flat_map(&clip_polyline/1)
        |> Enum.reject(&(length(&1) < 4))
        |> Enum.map(fn line -> line |> decimate(5) |> chaikin(2) |> simplify(1.0) end)
    end
  end

  # -- drawing ---------------------------------------------------------

  # Emit integer-px deltas with error diffusion: each delta is rounded
  # against the TRUE position, not the previous rounded delta, so sub-pixel
  # steps cannot accumulate into axis-aligned staircases (the NAPLPS relative
  # encoding resolves 1/256 per axis independently).
  defp draw_polyline(buffer, [{x0, y0} | rest]) do
    ex0 = round(x0)
    ey0 = round(y0)

    {deltas, _} =
      Enum.reduce(rest, {[], {ex0, ey0}}, fn {x, y}, {acc, {ex, ey}} ->
        dx = round(x) - ex
        dy = round(y) - ey

        if dx == 0 and dy == 0 do
          {acc, {ex, ey}}
        else
          {[{dx / 256, dy / 256} | acc], {ex + dx, ey + dy}}
        end
      end)

    case Enum.reverse(deltas) do
      [] ->
        buffer

      ds ->
        buffer
        |> draw(@cmd_set_point_abs, [{ex0 / 256, ey0 / 256}])
        |> draw(@cmd_line_rel, ds)
    end
  end

  # Ramer-Douglas-Peucker: drop points within `epsilon` px of the simplified
  # line - visually lossless at 1 px, and the byte win is large because the
  # corner-cutting pass leaves long near-collinear runs.
  defp simplify(points, _epsilon) when length(points) < 3, do: points

  defp simplify(points, epsilon) do
    first = List.first(points)
    last = List.last(points)

    {max_d, max_i} =
      points
      |> Enum.with_index()
      |> Enum.map(fn {p, i} -> {perp_distance(p, first, last), i} end)
      |> Enum.max_by(&elem(&1, 0))

    if max_d > epsilon do
      left = simplify(Enum.take(points, max_i + 1), epsilon)
      right = simplify(Enum.drop(points, max_i), epsilon)
      left ++ tl(right)
    else
      [first, last]
    end
  end

  defp perp_distance({px, py}, {ax, ay}, {bx, by}) do
    dx = bx - ax
    dy = by - ay
    len_sq = dx * dx + dy * dy

    if len_sq == 0 do
      :math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay))
    else
      t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / len_sq))
      cx = ax + t * dx
      cy = ay + t * dy
      :math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
    end
  end

  # Keep points at least `min_dist` px apart (endpoints always kept) so the
  # corner-cutting pass works on real geometry, not sub-pixel stubble.
  defp decimate([first | rest] = points, min_dist) do
    kept =
      rest
      |> Enum.reduce([first], fn {x, y} = p, [{lx, ly} | _] = acc ->
        if :math.sqrt((x - lx) * (x - lx) + (y - ly) * (y - ly)) >= min_dist do
          [p | acc]
        else
          acc
        end
      end)
      |> Enum.reverse()

    last = List.last(points)
    if List.last(kept) == last, do: kept, else: kept ++ [last]
  end

  # -- pressure grid ---------------------------------------------------

  # Returns {lats, lons, %{{row, col} => hPa}} or nil.  Rows follow lats,
  # cols follow lons; MSLP is defined over ocean too, so the grid is dense.
  defp pressure_grid(cache_dir, date) do
    File.mkdir_p(cache_dir)
    cache_file = Path.join(cache_dir, "isobar-msl-#{Date.to_iso8601(date)}.json")

    lats = WeatherGrid.grid_lat_lons() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    lons = WeatherGrid.grid_lat_lons() |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    points =
      with {:ok, cached} <- File.read(cache_file),
           {:ok, decoded} <- Jason.decode(cached) do
        decoded
      else
        _ ->
          {fetched, failed_batches} = fetch_all()

          # Cache only complete fetches - a failed batch must not freeze a
          # gap into the isobars for the rest of the day.
          if fetched != [] and failed_batches == 0,
            do: File.write(cache_file, Jason.encode!(fetched))

          fetched
      end

    case points do
      [] ->
        nil

      _ ->
        # Snap-keyed (not float-keyed): exact float matching against the
        # re-accumulated grid would silently empty if float_range changed.
        by_pos = Map.new(points, fn [lat, lon, msl] -> {snap_key(lat, lon), msl} end)

        values =
          for {lat, r} <- Enum.with_index(lats),
              {lon, c} <- Enum.with_index(lons),
              msl = by_pos[snap_key(lat, lon)],
              is_number(msl),
              into: %{} do
            {{r, c}, msl}
          end

        {lats, lons, values}
    end
  end

  defp fetch_all do
    WeatherGrid.grid_lat_lons()
    |> Enum.chunk_every(@batch_size)
    |> Enum.with_index(1)
    |> Enum.reduce({[], 0}, fn {batch, i}, {points, failed} ->
      case fetch_batch(batch) do
        {:ok, batch_points} ->
          {points ++ batch_points, failed}

        {:error, reason} ->
          Logger.warning("isobar batch #{i} failed: #{inspect(reason)}")
          {points, failed + 1}
      end
    end)
  end

  defp fetch_batch(lat_lons) do
    la = Enum.map_join(lat_lons, ",", &elem(&1, 0))
    lo = Enum.map_join(lat_lons, ",", &elem(&1, 1))

    query =
      URI.encode_query(%{
        "latitude" => la,
        "longitude" => lo,
        "hourly" => "pressure_msl",
        "forecast_days" => 1,
        "timezone" => "UTC"
      })

    with {:ok, response} <- WeatherGrid.get_with_retry(@endpoint <> "?" <> query, 3),
         200 <- response.status_code,
         {:ok, decoded} <- Jason.decode(response.body) do
      locations = List.wrap(decoded)

      points =
        for {loc, {lat, lon}} <- Enum.zip(locations, lat_lons),
            msl = mean_msl(loc),
            is_number(msl) do
          [lat, lon, msl]
        end

      {:ok, points}
    else
      err -> {:error, err}
    end
  end

  # Mean of the first 12 forecast hours - one representative synoptic state,
  # consistent with how the grid treats sky and wind.
  defp mean_msl(location) do
    values =
      location
      |> get_in(["hourly", "pressure_msl"])
      |> List.wrap()
      |> Enum.filter(&is_number/1)
      |> Enum.take(12)

    case values do
      [] -> nil
      vs -> Enum.sum(vs) / length(vs)
    end
  end

  # 3x3 neighbor-mean smoothing over the (possibly holey) grid.
  defp smooth(values, lats, lons) do
    rows = length(lats)
    cols = length(lons)

    for r <- 0..(rows - 1), c <- 0..(cols - 1), values[{r, c}], into: %{} do
      neighborhood =
        for dr <- -1..1, dc <- -1..1, v = values[{r + dr, c + dc}], is_number(v), do: v

      {{r, c}, Enum.sum(neighborhood) / length(neighborhood)}
    end
  end

  # Chaikin corner cutting: each pass replaces every interior segment with its
  # 1/4 and 3/4 points, rounding the coarse grid's angles into curves.
  defp chaikin(points, 0), do: points
  defp chaikin([_] = points, _n), do: points
  defp chaikin([_, _] = points, _n), do: points

  defp chaikin(points, n) do
    first = List.first(points)
    last = List.last(points)

    cut =
      points
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.flat_map(fn [{x1, y1}, {x2, y2}] ->
        [
          {x1 * 0.75 + x2 * 0.25, y1 * 0.75 + y2 * 0.25},
          {x1 * 0.25 + x2 * 0.75, y1 * 0.25 + y2 * 0.75}
        ]
      end)

    chaikin([first] ++ cut ++ [last], n - 1)
  end

  # -- contouring (marching squares) -----------------------------------

  defp levels(values) do
    {min_v, max_v} = values |> Map.values() |> Enum.min_max()
    lo = ceil(min_v / @interval_hpa) * @interval_hpa
    hi = floor(max_v / @interval_hpa) * @interval_hpa
    if lo > hi, do: [], else: Enum.take_while(Stream.iterate(lo, &(&1 + @interval_hpa)), &(&1 <= hi))
  end

  # March each grid cell; emit line segments in {lat, lon} space, then chain
  # shared endpoints into polylines.
  defp contour(lats, lons, values, level) do
    rows = length(lats)
    cols = length(lons)
    lat_arr = List.to_tuple(lats)
    lon_arr = List.to_tuple(lons)

    segments =
      for r <- 0..(rows - 2), c <- 0..(cols - 2), reduce: [] do
        acc ->
          with v00 when is_number(v00) <- values[{r, c}],
               v01 when is_number(v01) <- values[{r, c + 1}],
               v10 when is_number(v10) <- values[{r + 1, c}],
               v11 when is_number(v11) <- values[{r + 1, c + 1}] do
            la0 = elem(lat_arr, r)
            la1 = elem(lat_arr, r + 1)
            lo0 = elem(lon_arr, c)
            lo1 = elem(lon_arr, c + 1)

            cell_segments({v00, v01, v10, v11}, {la0, la1, lo0, lo1}, level) ++ acc
          else
            _ -> acc
          end
      end

    chain(segments)
  end

  # Corner layout (lat up, lon right):  v10 -- v11     edges: top t, bottom b,
  #                                     v00 -- v01            left l, right r
  defp cell_segments({v00, v01, v10, v11}, {la0, la1, lo0, lo1}, level) do
    b00 = if v00 >= level, do: 1, else: 0
    b01 = if v01 >= level, do: 2, else: 0
    b11 = if v11 >= level, do: 4, else: 0
    b10 = if v10 >= level, do: 8, else: 0
    index = b00 + b01 + b11 + b10

    # Guard the flat-field case: equal corners can only bracket `level` when
    # both equal it - put the crossing mid-edge.
    t = fn
      a, a2 when a2 == a -> 0.5
      a, b -> (level - a) / (b - a)
    end
    bottom = {la0, lo0 + t.(v00, v01) * (lo1 - lo0)}
    top = {la1, lo0 + t.(v10, v11) * (lo1 - lo0)}
    left = {la0 + t.(v00, v10) * (la1 - la0), lo0}
    right = {la0 + t.(v01, v11) * (la1 - la0), lo1}

    case index do
      0 -> []
      15 -> []
      1 -> [{left, bottom}]
      14 -> [{left, bottom}]
      2 -> [{bottom, right}]
      13 -> [{bottom, right}]
      4 -> [{right, top}]
      11 -> [{right, top}]
      8 -> [{top, left}]
      7 -> [{top, left}]
      3 -> [{left, right}]
      12 -> [{left, right}]
      6 -> [{bottom, top}]
      9 -> [{bottom, top}]
      # saddles: split arbitrarily but consistently
      5 -> [{left, top}, {bottom, right}]
      10 -> [{left, bottom}, {top, right}]
    end
  end

  # Chain segments that share endpoints into polylines (endpoints quantized
  # for float-safe matching).
  defp chain(segments) do
    keyed = Enum.map(segments, fn {a, b} -> {key(a), key(b), a, b} end)

    adjacency =
      Enum.reduce(keyed, %{}, fn {ka, kb, a, b}, acc ->
        acc
        |> Map.update(ka, [{kb, a, b}], &[{kb, a, b} | &1])
        |> Map.update(kb, [{ka, b, a}], &[{ka, b, a} | &1])
      end)

    walk_chains(keyed, adjacency, MapSet.new(), [])
  end

  defp walk_chains([], _adjacency, _used, chains), do: chains

  defp walk_chains([{ka, kb, a, b} | rest], adjacency, used, chains) do
    seg_id = seg_key(ka, kb)

    if MapSet.member?(used, seg_id) do
      walk_chains(rest, adjacency, used, chains)
    else
      used = MapSet.put(used, seg_id)
      {tail_points, used} = extend(kb, b, adjacency, used)
      {head_points, used} = extend(ka, a, adjacency, used)
      chain = Enum.reverse(head_points) ++ [a, b] ++ tail_points
      walk_chains(rest, adjacency, used, [chain | chains])
    end
  end

  defp extend(from_key, _from_point, adjacency, used) do
    neighbors = Map.get(adjacency, from_key, [])

    # A node where 3+ segments meet is a junction (noise/saddle artifact);
    # walking through it tangles unrelated contour branches into one line.
    candidates = if length(neighbors) > 2, do: [], else: neighbors

    case Enum.find(candidates, fn {kn, _pa, _pb} ->
           not MapSet.member?(used, seg_key(from_key, kn))
         end) do
      nil ->
        {[], used}

      {kn, _pa, pb} ->
        used = MapSet.put(used, seg_key(from_key, kn))
        {more, used} = extend(kn, pb, adjacency, used)
        {[pb | more], used}
    end
  end

  defp key({lat, lon}), do: {round(lat * 100), round(lon * 100)}
  defp seg_key(k1, k2), do: if(k1 <= k2, do: {k1, k2}, else: {k2, k1})

  # -- land mask -------------------------------------------------------

  # NDFD only returns forecasts over land, so the temperature grid doubles as
  # a CONUS land mask at grid resolution: a contour point is "on land" when
  # its nearest grid node came back with data.
  defp land_mask(cache_dir, date) do
    WeatherGrid.fetch_grid(cache_dir, date)
    |> Enum.map(fn %{lat: lat, lon: lon} -> snap_key(lat, lon) end)
    |> MapSet.new()
  end

  defp snap_key(lat, lon) do
    {round((lat - 25.0) / 1.5), round((lon + 124.0) / 1.5)}
  end

  # Split a lat/lon polyline into runs of on-land points - nothing over water.
  defp clip_to_land(points, land) do
    points
    |> Enum.chunk_by(fn {lat, lon} -> MapSet.member?(land, snap_key(lat, lon)) end)
    |> Enum.filter(fn [{lat, lon} | _] -> MapSet.member?(land, snap_key(lat, lon)) end)
  end

  # -- projection + clipping -------------------------------------------

  defp to_gcu_px(points) do
    Enum.map(points, fn {lat, lon} ->
      {x, y} = WeatherMapper.geo_to_gcu({lon, lat})
      {x * 256, y * 256}
    end)
  end

  # Split a polyline into runs of in-bounds points (dropping excursions off
  # the map instead of drawing to the border).
  defp clip_polyline(points) do
    points
    |> Enum.chunk_by(&in_bounds?/1)
    |> Enum.filter(fn run -> in_bounds?(hd(run)) end)
  end

  # Bounds come from WeatherPlacement.map_bounds/0 - one source of truth
  # for the region every layer places/clips against.
  defp in_bounds?({x, y}) do
    {min_x, max_x, min_y, max_y} = WeatherPlacement.map_bounds()
    x >= min_x and x <= max_x and y >= min_y and y <= max_y
  end
end
