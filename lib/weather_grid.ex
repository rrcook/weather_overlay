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

defmodule WeatherGrid do
  @moduledoc """
  A uniform forecast grid over the continental US, fetched from the NDFD
  multi-point service (graphical.weather.gov DWML).

  The temperature "communities" need evenly-spaced samples - the hand-picked
  station list is population-biased and far too sparse (clusters would find
  cities, not weather).  We define our own ~1.5 degree grid (~650 points),
  batch it through NDFDgenLatLonList, and cache the parsed result per day so
  development re-runs do not hammer NOAA.

  Returns points as `%{lat, lon, maxt}` - today's forecast daily-maximum
  temperature, matching the map's "Today's Forecast" framing.
  """
  require Logger

  @endpoint "https://graphical.weather.gov/xml/sample_products/browser_interface/ndfdXMLclient.php"

  # CONUS bounding box, 1.5 degree spacing (~650 points before NDFD drops
  # off-grid/ocean cells).
  @min_lon -124.0
  @max_lon -68.0
  @min_lat 25.0
  @max_lat 49.0
  @spacing 1.5

  @batch_size 100
  # These multi-point requests routinely take 5-15 s each.
  @recv_timeout 60_000

  @doc "The uniform lat/lon grid, as {lat, lon} tuples."
  def grid_lat_lons do
    lats = float_range(@min_lat, @max_lat, @spacing)
    lons = float_range(@min_lon, @max_lon, @spacing)
    for lat <- lats, lon <- lons, do: {lat, lon}
  end

  defp float_range(from, to, step) do
    Stream.iterate(from, &(&1 + step)) |> Enum.take_while(&(&1 <= to))
  end

  @doc """
  Today's max-temperature grid, cached under `cache_dir` (one JSON file per
  date).  On fetch failure returns whatever points were retrieved (possibly
  `[]`) - a degraded map beats no map.
  """
  def fetch_maxt_grid(cache_dir, date \\ Date.utc_today()) do
    File.mkdir_p(cache_dir)
    prune_stale(cache_dir, date)
    cache_file = Path.join(cache_dir, "ndfd-maxt-#{Date.to_iso8601(date)}.json")

    with {:ok, cached} <- File.read(cache_file),
         {:ok, points} <- Jason.decode(cached) do
      Logger.debug("NDFD grid: #{length(points)} cached points (#{cache_file})")
      Enum.map(points, &%{lat: &1["lat"], lon: &1["lon"], maxt: &1["maxt"]})
    else
      _ ->
        {points, failed_batches} = fetch_all_batches()

        # Cache only complete fetches: a transiently failed batch must not
        # freeze a hole into the map for the rest of the day.
        if points != [] and failed_batches == 0 do
          File.write(cache_file, Jason.encode!(points))
        end

        points
    end
  end

  defp fetch_all_batches do
    grid_lat_lons()
    |> Enum.chunk_every(@batch_size)
    |> Enum.with_index(1)
    |> Enum.reduce({[], 0}, fn {batch, i}, {points, failed} ->
      case fetch_batch(batch) do
        {:ok, batch_points} ->
          {points ++ batch_points, failed}

        {:error, reason} ->
          Logger.warning("NDFD grid batch #{i} failed: #{inspect(reason)}")
          {points, failed + 1}
      end
    end)
  end

  defp fetch_batch(lat_lons) do
    list = Enum.map_join(lat_lons, " ", fn {lat, lon} -> "#{lat},#{lon}" end)

    query =
      URI.encode_query(%{
        "whichClient" => "NDFDgenLatLonList",
        "listLatLon" => list,
        "product" => "time-series",
        "Unit" => "e",
        "maxt" => "maxt"
      })

    with {:ok, response} <- get_with_retry(@endpoint <> "?" <> query, 3),
         200 <- response.status_code do
      {:ok, parse_dwml(response.body)}
    else
      err -> {:error, err}
    end
  end

  @doc """
  Parse a DWML time-series response into `[%{lat, lon, maxt}]`, taking the
  first (today's) maximum-temperature value per point.  Points the NDFD grid
  does not cover (ocean, off-CONUS) come back without usable values and are
  dropped.  Only the `<data>` section is parsed - the `<head>` contains mixed
  content that XmlToMap cannot represent.
  """
  def parse_dwml(xml) do
    with [_, rest] <- String.split(xml, "<data>", parts: 2),
         [data_xml, _] <- String.split(rest, "</data>", parts: 2),
         {:ok, parsed} <- naive_map("<data>" <> data_xml <> "</data>") do
      data = parsed["data"]
      locations = data["location"] |> List.wrap()
      parameters = data["parameters"] |> List.wrap()

      coords =
        for loc <- locations,
            key = loc["location-key"],
            point = loc["point"],
            into: %{} do
          {key,
           {parse_float(point["-latitude"]), parse_float(point["-longitude"])}}
        end

      for params <- parameters,
          key = params["-applicable-location"],
          {lat, lon} <- [coords[key]],
          maxt <- [first_temp(params)],
          is_number(maxt) and is_number(lat) and is_number(lon) do
        %{lat: lat, lon: lon, maxt: maxt}
      end
    else
      _ ->
        Logger.warning("NDFD grid: unparseable DWML response")
        []
    end
  end

  @doc "GET with retry on 429 rate limiting (shared by the fetch modules)."
  def get_with_retry(url, attempts_left) do
    case HTTPoison.get(url, [], recv_timeout: @recv_timeout) do
      {:ok, %{status_code: 429}} when attempts_left > 1 ->
        Process.sleep(30_000)
        get_with_retry(url, attempts_left - 1)

      other ->
        other
    end
  end

  # Drop cache files from previous days so output/cache does not grow forever.
  defp prune_stale(cache_dir, date) do
    iso = Date.to_iso8601(date)

    case File.ls(cache_dir) do
      {:ok, files} ->
        for f <- files, String.ends_with?(f, ".json"), not String.contains?(f, iso) do
          File.rm(Path.join(cache_dir, f))
        end

        :ok

      _ ->
        :ok
    end
  end

  defp naive_map(xml) do
    try do
      {:ok, XmlToMap.naive_map(xml)}
    catch
      _, _ -> {:error, :xml_parse_error}
    end
  end

  defp first_temp(params) do
    params
    |> get_in(["#content", "temperature", "#content", "value"])
    |> List.wrap()
    |> List.first()
    |> parse_int()
  end

  defp parse_float(nil), do: nil

  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_int(nil), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp parse_int(_), do: nil
end
