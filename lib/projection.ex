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

defmodule WeatherOverlay.Projection do
  @moduledoc """
  Pure-Elixir replacement for the single PROJ projection this app used:
  EPSG:2163, the US National Atlas Equal Area coordinate system.

  PROJ.4 definition:

      +proj=laea +lat_0=45 +lon_0=-100 +x_0=0 +y_0=0 +a=6370997 +b=6370997 +units=m +no_defs

  Because the ellipsoid is a sphere (a == b), this is the spherical oblique
  Lambert Azimuthal Equal Area projection, which has a closed form (Snyder,
  *Map Projections – A Working Manual*, USGS PP 1395, eqs. 22-4/24-2..24-4).
  Output matches libproj's `pj_transform` from WGS84 to within ~5e-5 m across
  the continental US, so it fully replaces the `:proj` C NIF for this app.
  """

  @radius 6_370_997.0
  @lat_0 45.0 * :math.pi() / 180.0
  @lon_0 -100.0 * :math.pi() / 180.0
  @deg_to_rad :math.pi() / 180.0

  @sin_lat_0 :math.sin(@lat_0)
  @cos_lat_0 :math.cos(@lat_0)

  @doc """
  Projects a WGS84 `{latitude, longitude}` pair (degrees) to EPSG:2163
  `{easting, northing}` in metres.

  Drop-in replacement for `Proj.from_lat_lng!({lat, lng}, epsg_2163_proj)`.
  """
  @spec from_lat_lng!({number(), number()}) :: {float(), float()}
  def from_lat_lng!({latitude, longitude}) do
    phi = latitude * @deg_to_rad
    d_lambda = longitude * @deg_to_rad - @lon_0

    sin_phi = :math.sin(phi)
    cos_phi = :math.cos(phi)
    cos_d_lambda = :math.cos(d_lambda)

    # k' = sqrt(2 / (1 + cos c)), the equal-area scale factor.
    k = :math.sqrt(2.0 / (1.0 + @sin_lat_0 * sin_phi + @cos_lat_0 * cos_phi * cos_d_lambda))

    x = @radius * k * cos_phi * :math.sin(d_lambda)
    y = @radius * k * (@cos_lat_0 * sin_phi - @sin_lat_0 * cos_phi * cos_d_lambda)

    {x, y}
  end
end
