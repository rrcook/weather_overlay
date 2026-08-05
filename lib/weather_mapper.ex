# Copyright 2024,2025,2026 Ralph Richard Cook
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

defmodule WeatherMapper do
  require Logger
  import NaplpsWriter
  use NaplpsConstants

  # Constants used for geographic conversion, latitude & longitude to Prodigy X, Y

  # @min_longitude        -124.10
  # @min_longitude -126.10
  # @max_longitude        -68.12
  # @longitude_factor 3.7692

  # @min_latitude 25.1
  # @max_latitude         49.03
  # @latitude_factor 5.375

  # The x's and y's from looking at an equal area (laea, epsg 2163) map and inputting the
  # latitude and longitude into Proj, getting the x and y back.
  @west_2163 -2_027_511
  @east_2163 2_514_264
  @south_2163 -2_102_532
  @north_2163 717_248

  # the x' and y's from GCU, looking at the weather map in GCU and getting the x and y
  # from the cursor.
  @min_x 36
  @max_x 253
  @min_y 53
  @max_y 182

  @max_temp_x 240 / 256

  @min_x_range 36 / 256
  @max_x_range 253 / 256
  @min_y_range 53 / 256
  @max_y_range 182 / 256

  @x_factor (@max_x - @min_x) / (@east_2163 - @west_2163)
  @y_factor (@max_y - @min_y) / (@north_2163 - @south_2163)

  @rain_features ["Rain", "Rain/Thunderstorms", "Heavy Rain/Flash Flooding Possible", "Severe Thunderstorms Possible"]
  @wo_fn_map %{
    "Severe Thunderstorms Possible" => &WeatherObjects.draw_lightning/2
  }

  # Cloud features may be used later.
  # @cloud_features ["Cloudy", "Partly Cloudy", "Mostly Cloudy"]
  @snow_features ["Rain/Snow", "Snow", "Heavy Snow Possible"]

  @text_width 6
  @text_height 10

  defp meters_to_x(meters), do: (meters - @west_2163) * @x_factor + @min_x

  defp meters_to_y(meters), do: (meters - @south_2163) * @y_factor + @min_y

  def within_continental({x, y}) do
    x >= @min_x_range &&
      x <= @max_x_range &&
      y >= @min_y_range &&
      y <= @max_y_range
  end

  defp equalarea() do
    # In the interest of performance and calling this a lot we assume that
    # the table is there and set up
    [equal_area: proj] = :ets.lookup(:weather, :equal_area)
    proj
  end

  # The small lists from the feature collection are longitude, latitude, not lat, long
  def geo_to_gcu({longitude, latitude}) do
    {x_meters, y_meters} = Proj.from_lat_lng!({latitude, longitude}, equalarea())
    {meters_to_x(x_meters) / 256, meters_to_y(y_meters) / 256}
  end

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

  # Used for filtering functions
  def is_ok({:ok, _}), do: true
  def is_ok(_), do: false

  # Simple check for status code for HTTP response codes
  defp status_check(200), do: {:ok, 200}
  defp status_check(status_code), do: {:error, status_code}

  # Used to make proper polygons for rain maps
  # The original coordinates from the govt are absolutes in [lat, long], we need to convert
  # them to {x, y} relative

  # This function takes a list of values and converts it to a starting value and
  # the difference needed to get to the next value.
  defp diff_list(values), do: diff_list([0 | values], [])
  defp diff_list([_head], acc), do: Enum.reverse(acc)
  defp diff_list([head | tail], acc), do: diff_list(tail, [hd(tail) - head | acc])

  # Takes the feature collection [lat, long] lists and converts them to a list of
  # tuples with the lat and long differences
  def fc_to_diffs(lat_longs) do
    {lats, longs} = lat_longs |> Enum.map(&List.to_tuple/1) |> Enum.unzip()
    Enum.zip(diff_list(lats), diff_list(longs))
  end

  # "Railway" wrapper around our xml to map function, will return a tuple with
  # :ok or :error
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

  # See if a feature collection json has a particular feature.
  # Each feature has json data but will have empty coordinates if the feature isn't
  # in today's weather.
  def has_feature(fc_json, feature) do
    feature = Enum.filter(fc_json["features"], &(&1["name"] == feature)) |> Enum.at(0)

    case feature do
      nil -> false
      _ -> feature["geometry"]["coordinates"] |> Enum.at(0) |> length > 0
    end
  end

  # Draw a legend rectangle for rain or snow
  def add_rain_legend(buffer, lower_y) do
    add_legend(buffer, "Rain", @color_black, lower_y)
  end

  def add_snow_legend(buffer, lower_y) do
    add_legend(buffer, "Snow", @color_white, lower_y)
  end

  def add_legend(buffer, _label, _legend_color, lower_y) when lower_y < 0, do: buffer

  def add_legend(buffer, label, legend_color, lower_y) do
    buffer
    |> select_color(@color_gray)
    |> append_bytes([@cmd_texture_attr, @hatching_solid])
    |> draw(@cmd_set_rect_filled, [{0, lower_y / 256}, {31 / 256, 27 / 256}])
    |> select_color(legend_color)
    |> append_bytes([@cmd_texture_attr, @hatching_vertical])
    |> draw(@cmd_set_rect_filled, [{2 / 256, (lower_y + 12) / 256}, {23 / 256, 11 / 256}])
    |> draw(@cmd_set_rect_outlined, [{2 / 256, (lower_y + 12) / 256}, {23 / 256, 11 / 256}])
    |> draw_text_abs(label, [{3 / 256, (lower_y + 2) / 256}])
  end

  # Take NOAA temperature XML to get a longitude, latitude and temperature in fahrenheit
  @spec get_location_temp((any() -> any()), any()) :: any()
  def get_location_temp(get_fn, get_text) do
    with {:ok, response} <- get_fn.(get_text),
         {:ok, 200} <- status_check(response.status_code),
         {:ok, w_map} <- ex_naive_map(response.body),
         {:ok, latitude} <- nil_check(w_map["current_observation"]["#content"]["latitude"]),
         {:ok, longitude} <- nil_check(w_map["current_observation"]["#content"]["longitude"]),
         {:ok, temp_f} <- nil_check(w_map["current_observation"]["#content"]["temp_f"]) do
      {:ok, {{String.to_float(longitude), String.to_float(latitude)}, String.to_float(temp_f)}}
    else
      err ->
      Logger.warning("Problem retrieving temperature for #{get_text}, #{inspect(err)}")
      err
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
  # Make each list, xs and ys, into lists of differences from the
  #  starting point
  # zip the lists back into {x, y} pairs
  def convert_poly(poly) do
    {xs, ys} =
      poly
      |> Enum.map(&List.to_tuple/1)
      |> Enum.map(&geo_to_gcu/1)
      # |> IO.inspect()
      |> Enum.unzip()

    {diff_xs, diff_ys} = {diff_list(xs), diff_list(ys)}

    Enum.zip(diff_xs, diff_ys)
    # |> IO.inspect()
  end

  # Draw a polygon and properly terminate it in the GCU style.
  # Each NOAA feature may have multiple polygons
  def draw_one_poly(buffer, xys) do
    buffer
    |> draw(@cmd_set_poly_filled, xys)
    |> draw(@cmd_set_point_rel, [])
  end

  # Not your average average function!
  # The input list has the starting point at the head, then the rest of
  # the values are delta from the previous accumulated values.
  # This is what GCU and Prodigy expects for the NAPLPS commands x, y values.
  # This means to get the average of the absolute values we need to keep track
  # of the accumulated values as we go along. This function calculates the
  # sum of those values so far and the count, then uses that to get the average.
  def avg_delta(list) do
    {sum, count, _acc} =
      Enum.reduce(list, {0, 0, [0]}, fn x, {acc_sum, acc_count, acc_list} ->
        {acc_sum + x + hd(acc_list), acc_count + 1, [x + hd(acc_list) | acc_list]}
      end)
    sum / count
  end

  # This function sees if there is a corresponding weather object to draw for the
  # weather feature we're interested in
  # Recieves a list of lists, where the inner list is a list of {x, y}
  # to find the "center" we get an average of the x's and y's, then draw
  # our weather object there.
  # The weather objects would be put at the end so they're on top, so I'm saving them
  # in the Process dictionary until it's time to add them
  def save_weather_objects(feature_text, gcu_polys) do
    wo_fn = Map.get(@wo_fn_map, feature_text)

    case wo_fn do
      nil -> :ok
      _ ->
        Enum.each(gcu_polys, fn poly_list ->
          {xs, ys} = Enum.unzip(poly_list)
          wo_buffer = wo_fn.(<<>>, {avg_delta(xs), avg_delta(ys)})
          wos = Process.get(:wo, [])
          Process.put(:wo, [wo_buffer | wos])
        end)
    end
  end

  # Use the NOAA feature collection specified in json to get the desired feature.
  # Extract the polygon for the feature passed in as feature_text
  # Draw hatching in the color specified.
  def draw_weather_poly(buffer, json, feature_text, color) do
    feature = Enum.filter(json["features"], &(&1["name"] == feature_text)) |> Enum.at(0)

    feature_polys =
      case feature do
        nil -> []
        _ -> feature["geometry"]["coordinates"] |> Enum.at(0)
      end

    case feature_polys do
      [] ->
        buffer

      _ ->
        gcu_polys = Enum.map(feature_polys, &convert_poly/1)
        save_weather_objects(feature_text, gcu_polys)

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

  # Take a list of features and add the weather polygons for each one,
  # drawn in the appropriate color. Join the polygons together.
  def draw_weather_features(buffer, json, feature_list, color) do
    feature_bufs =
      Enum.map(feature_list, fn feature ->
        draw_weather_poly(<<>>, json, feature, color)
      end)
      |> IO.iodata_to_binary()

    buffer <> feature_bufs
  end

  # For a list of NOAA XML url's get weather information. XML format.
  # Get each XML in parallel, pass along only ones that come back :ok.
  def get_weather_temps(temp_urls) do
    temp_urls
    |> Enum.map(&Task.async(fn -> get_temp_from_url(&1) end))
    |> Enum.map(&Task.await/1)
    |> Enum.filter(&is_ok/1)
    |> Enum.map(&elem(&1, 1))
  end

  # Place the temperature text on the map.
  def place_temp(buffer, {xy, temp}) do
    {original_x, original_y} = xy
    # make sure the temp doesn't go off the right edge of the map, move it slightly left if necessary
    draw_x =
      if original_x > @max_temp_x do
        @max_temp_x
      else
        original_x
      end
    buffer
    |> draw_text_abs(temp, {draw_x, original_y})
  end

  # Get each x, y, temperature from a NOAA URL, convert the text to the
  # Prodigy temperature "range" (60s), write out the x & y.
  def make_weather_temps(buffer, temp_urls) do
    temp_buffer_list =
      get_weather_temps(temp_urls)
      |> Enum.map(&WeatherMapper.temp_to_gcutemp/1)
      |> Enum.map(fn gcu_temp -> place_temp(<<>>, gcu_temp) end)

    buffer <> IO.iodata_to_binary(temp_buffer_list)
  end

  # Read through the feature collection json and extract every high and low
  # pressure center inside the continental US rectangle, as
  # {:high | :low, {x, y}} in GCU px - the input WeatherPlacement thins to
  # the sparse 2-4 mark look of the original maps.
  def extract_pressure_centers(json) do
    for {name, type} <- [{"high", :high}, {"low", :low}],
        feature <- Enum.filter(json["features"], &(&1["name"] == name)),
        xy = feature["geometry"]["coordinates"] |> List.to_tuple() |> geo_to_gcu(),
        within_continental(xy) do
      {x, y} = xy
      {type, {x * 256, y * 256}}
    end
  end

  # Thinned pressure callouts as collision boxes (lower-left, GCU px).
  # Pressures place first (priority 0) - the originals never let a temp
  # crowd out an H/L.
  def build_pressure_callouts(json) do
    json
    |> extract_pressure_centers()
    |> WeatherPlacement.thin_pressures()
    |> Enum.map(fn {type, {cx, cy}} ->
      # Put the x,y as the center of the text, width is 6, height is 10
      %{
        kind: type,
        label: nil,
        x: cx - @text_width / 2,
        y: cy - @text_height / 2,
        w: @text_width,
        h: @text_height,
        priority: 0
      }
    end)
  end

  @temp_callout_budget 15

  # Temperature-community callouts from the NDFD forecast grid: uniform
  # samples -> k-means communities labeled by modal decade -> interior
  # same-decade communities become words ("warm").  Collision boxes,
  # priority 1.
  def build_temp_callouts(cache_dir) do
    WeatherGrid.fetch_maxt_grid(cache_dir)
    |> Enum.flat_map(fn %{lat: lat, lon: lon, maxt: maxt} ->
      xy = geo_to_gcu({lon, lat})

      if within_continental(xy) do
        {x, y} = xy
        [%{x: x * 256, y: y * 256, temp: maxt}]
      else
        []
      end
    end)
    |> WeatherPlacement.temp_communities(@temp_callout_budget)
    |> WeatherPlacement.label_temp_communities()
    |> Enum.map(fn %{x: cx, y: cy, kind: kind, label: label} ->
      w = @text_width * String.length(label)

      %{
        kind: kind,
        label: label,
        x: cx - w / 2,
        y: cy - @text_height / 2,
        w: w,
        h: @text_height,
        priority: 1
      }
    end)
  end

  def draw_pressures(buffer, placed, type, pressure_letter) do
    placed
    |> Enum.filter(&(&1.kind == type))
    |> Enum.reduce(buffer, fn %{x: x, y: y}, buf ->
      draw_text_abs(buf, pressure_letter, {x / 256, y / 256})
    end)
  end

  # Using a json body of NOAA "feature collections", draw polygons for selected weather features,
  # then the already-placed high and low pressure callouts.
  def make_fc_weather(buffer, fc_json, placed_callouts) do
    has_rain_feature = Enum.any?(@rain_features, fn x -> has_feature(fc_json, x) end)
    has_snow_feature = Enum.any?(@snow_features, fn x -> has_feature(fc_json, x) end)

    {rain_y, snow_y} =
      case {has_rain_feature, has_snow_feature} do
        {false, false} -> {-1, -1}
        {true, false} -> {54, -1}
        {false, true} -> {-1, 54}
        {true, true} -> {54, 81}
      end

    weather_buffer = gcu_init(buffer)
    |> append_byte(@cmd_shift_in)
    # These two calls could potentionally add weather objects to our Process dictionary
    |> draw_weather_features(fc_json, @rain_features, @color_black)
    |> draw_weather_features(fc_json, @snow_features, @color_white)
    |> select_color(@color_blue)
    |> draw_pressures(placed_callouts, :high, "H")
    |> select_color(@color_red)
    |> draw_pressures(placed_callouts, :low, "L")
    |> add_rain_legend(rain_y)
    |> add_snow_legend(snow_y)

    wos = Process.get(:wo, [])
    weather_buffer <> IO.iodata_to_binary(wos)
  end

  def get_temps_from_json(weather_json) do
    Enum.map(weather_json["regions"], fn r -> Enum.shuffle(r["region"]) |> Enum.take(2) end)
    |> Enum.flat_map(&Function.identity/1)
  end

  # Write the placed temperature / word callouts, plus a headline.
  def make_text(buffer, placed_callouts) do
    temps = Enum.filter(placed_callouts, &(&1.kind in [:temp, :word]))

    gcu_init(buffer)
    |> text_attributes({@text_width / 256, @text_height / 256})
    |> select_color(@color_yellow)
    |> then(fn buf ->
      Enum.reduce(temps, buf, fn %{label: label, x: x, y: y}, b ->
        draw_text_abs(b, label, {x / 256, y / 256})
      end)
    end)
    |> select_color(@color_white)
    |> draw_text_abs("Prodigy Reloaded Today's Forecast", {80 / 256, 188 / 256})
    |> draw(@cmd_set_point_rel, [])
  end

  def make_weather_overlay() do
    file_location = __DIR__ <> "/../assets/station_info.json"
    output_path = __DIR__ <> "/../output/"

    # Make sure the directory is there. File.mkdir will return :ok or :error, it
    # doesn't matter so we don't check.
    File.mkdir(output_path)

    {weather_json, feature_collection_json} =
      with {:ok, buffer} <- File.read(file_location),
           {:ok, w_json} <- Jason.decode(buffer),
           {:ok, response} <- HTTPoison.get(w_json["feature_collection"]),
           {:ok, fc_json} <- Jason.decode(response.body) do
        {w_json, fc_json}
      else
        err ->
          Logger.warning("Problem retrieving weather features #{inspect(err)}")
          nil
      end

    if weather_json do
      # Place everything together so temps never sit on an H/L: pressures
      # first (priority 0), then temperature communities (priority 1).
      placed_callouts =
        (build_pressure_callouts(feature_collection_json) ++
           build_temp_callouts(output_path <> "cache"))
        |> WeatherPlacement.resolve_collisions()

      Logger.debug("Creating NAPLPS buffer")
      pd_buffer =
        make_fc_weather(<<>>, feature_collection_json, placed_callouts)
        |> make_text(placed_callouts)

      Logger.debug("Writing NAPLPS and presentation to output directory.")
      # WO is Weather Overlay
      File.write!(output_path <> "WO.NAP", pd_buffer)
      pd_seg = PresentationData.new(:presentation_data_naplps, pd_buffer)
      header = Header.new("WM00A000", "B", :page_element_object, [pd_seg])
      buffer = ObjectEncoder.encode(header)
      File.write!(output_path <> "WM00A000.B_1_8_1", buffer)
    else
      IO.puts("No changes at this time.")
    end

  end
end
