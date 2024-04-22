defmodule WeatherMapper do
  import NaplpsWriter
  use NaplpsConstants

  # Constants used for geographic conversion, latitude & longitude to Prodigy X, Y
  # @min_longitude        -124.10
  @min_longitude -126.10
  # @max_longitude        -68.12
  @longitude_factor 3.7692

  @min_latitude 25.1
  # @max_latitude         49.03
  @latitude_factor 5.375

  @min_x 36
  # @max_x                247
  @min_y 53
  # @max_y                182

  defp longitude_to_x(longitude), do: (longitude - @min_longitude) * @longitude_factor + @min_x

  defp latitude_to_y(latitude), do: (latitude - @min_latitude) * @latitude_factor + @min_y

  # The small lists from the feature collection are longitude, latitude, not lat, long
  def geo_to_gcu({longitude, latitude}),
    do: {longitude_to_x(longitude) / 256, latitude_to_y(latitude) / 256}

  # Round "down" temps, 63 -> 60, -15 -> -10. Used to set up basic weather temps
  defp temp_mod(temp) when temp < 0, do: -1 * temp_mod(abs(temp))
  defp temp_mod(temp) when temp == 0, do: 0
  defp temp_mod(temp), do: trunc(temp) - rem(trunc(temp), 10)

  defp temp_to_text(temp), do: Integer.to_string(temp_mod(temp)) <> "s"

  def temp_to_gcutemp({location, temp}) do
    {geo_to_gcu(location), temp_to_text(temp)}
  end

  # Quick check on the nested map, helps in the with statement
  defp nil_check(nil), do: {:error, nil}
  defp nil_check(value), do: {:ok, value}

  # Simple check for status code for HTTP response codes
  defp status_check(200), do: {:ok, 200}
  defp status_check(status_code), do: {:error, status_code}

  # Used for filtering functions
  def is_ok({:ok, _}), do: true
  def is_ok(_), do: false

  # Used to make proper polygons for rain maps
  # The original coordinates from the govt are absolutes in [lat, long], we need to convert
  # them to {x, y} relative

  # This function takes a list of values and converts it to a starting value and
  # the difference needed to get to the next value.
  defp diff_list([_head], acc), do: Enum.reverse(acc)
  defp diff_list([head | tail], acc), do: diff_list(tail, [hd(tail) - head | acc])
  defp diff_list(values), do: diff_list([0 | values], [])

  # Takes the feature collection [lat, long] lists and converts them to a list of
  # tuples with the lat and long differences
  def fc_to_diffs(lat_longs) do
    {lats, longs} = lat_longs |> Enum.map(&List.to_tuple/1) |> Enum.unzip()
    Enum.zip(diff_list(lats), diff_list(longs))
  end

  defp ex_naive_map(text) do
    try do
      xml_map = XmlToMap.naive_map(text)
      {:ok, xml_map}
    catch
      _err -> {:error, :xml_parse_error}
    end
  end

  # Pass in the way to get a temperature to process.
  def get_temp_from_url(url) do
    get_location_temp(&HTTPoison.get/1, url)
  end

  # Take NOAA temperature XML to get a longitude, latitude and temperature in fahrenheit
  def get_location_temp(get_fn, get_text) do
    with {:ok, response} <- get_fn.(get_text),
         {:ok, 200} <- status_check(response.status_code),
         {:ok, w_map} <- ex_naive_map(response.body),
         {:ok, latitude} <- nil_check(w_map["current_observation"]["#content"]["latitude"]),
         {:ok, longitude} <- nil_check(w_map["current_observation"]["#content"]["longitude"]),
         {:ok, temp_f} <- nil_check(w_map["current_observation"]["#content"]["temp_f"]) do
      {:ok, {{String.to_float(longitude), String.to_float(latitude)}, String.to_float(temp_f)}}
    else
      err -> err
    end
  end

  ##########################
  # Functions for drawing weather (rain, snow) polygons from NOAA feature collections
  ##########################

  # Convert NOAA polygon co-ordinates to GCU co-ordinates
  # The input poly is a list of [longitude, latitude]
  # The output poly is a list of {x, y} where the head is the starting point
  # and the tail is deltas from the previous point.
  # Convert to a list of tuples
  # Convert from {long, lat} to {gcu x, gcu y}
  # Unzip into two lists
  #

  def convert_poly(poly) do
    {xs, ys} =
      poly
      |> Enum.map(&List.to_tuple/1)
      |> Enum.map(&geo_to_gcu/1)
      |> IO.inspect()
      |> Enum.unzip()

    {diff_xs, diff_ys} = {diff_list(xs), diff_list(ys)}

    Enum.zip(diff_xs, diff_ys)
    |> IO.inspect()
  end

  # Draw a polygon and properly terminate it in the GCU style.
  # Each NOAA feature may have multiple polygons
  def draw_one_poly(buffer, xys) do
    buffer
    |> draw(@cmd_set_poly_filled, xys)
    |> draw(@cmd_set_point_rel, [])
  end

  # Use the NOAA feature collection specified in json to get the desired feature.
  # Extract the polygon for the feature passed in as feature_text
  # Draw hatching in the color specified.
  def draw_weather_poly(buffer, json, feature_text, color) do
    feature = Enum.filter(json["features"], &(&1["name"] == feature_text)) |> Enum.at(0)
    feature_polys = feature["geometry"]["coordinates"] |> Enum.at(0)

    case feature_polys do
      [] ->
        buffer

      _ ->
        gcu_polys = Enum.map(feature_polys, &convert_poly/1)

        drawn_polys =
          Enum.map(gcu_polys, &draw_one_poly(<<>>, &1))
          |> IO.iodata_to_binary()

        buffer
        |> select_color(color)
        |> append_bytes([@cmd_texture_attr, @hatching_vertical])
        |> append_bytes(drawn_polys)
        |> append_bytes([@cmd_texture_attr, @hatching_solid])
    end
  end
end
