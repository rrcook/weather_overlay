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

defmodule WeatherObjects do
  import NaplpsWriter
  use NaplpsConstants

  # orange star displacement
  @os_disp [
    {-0.04296875, -0.01171875},
    {0.0703125, 0.0546875},
    {-0.02734375, -0.09375},
    {-0.03125, 0.09375},
    {0.078125, -0.05859375},
    {-0.08984375, 0.00390625}
  ]

  # yellow arc displacement
  @ya_disp [{-0.0234375, 0.015625}, {0.046875, -0.02734375}]

  # yellow star displacement
  @ys_disp [
    {-0.03515625, -0.0390625},
    {0.0390625, 0.08984375},
    {0.0234375, -0.09765625},
    {-0.07421875, 0.06640625},
    {0.09375, 0.0},
    {-0.08203125, -0.05859375}
  ]

  # draw outline around fills as part of domain
  @texture_yes_outline <<@cmd_texture_attr, 0xC4, 0xC0, 0xD2, 0xC0>>
  @texture_partly <<@cmd_texture_attr, 0xC4>>

  @domain_new_pel <<@cmd_domain, 0xC8, 0xF8, 0xF8, 0xF9>>

  def draw_sun(buffer, {x, y}) do
    [{hx, hy} | t] = @os_disp
    orange_star = [{hx + x, hy + y} | t]
    [{hx, hy} | t] = @ya_disp
    yellow_arc = [{hx + x, hy + y} | t]
    [{hx, hy} | t] = @ys_disp
    yellow_star = [{hx + x, hy + y} | t]

    buffer
    |> select_color(@color_orange)
    |> draw(@cmd_set_poly_outlined, orange_star)
    |> append_byte(@cmd_set_point_rel)
    |> select_color(@color_yellow)
    |> draw(@cmd_set_arc_filled, yellow_arc)
    |> append_byte(@cmd_set_point_rel)
    |> draw(@cmd_set_poly_outlined, yellow_star)
    |> append_byte(@cmd_set_point_rel)
    |> gcu_init
  end

  # white cloud for cloudy
  @cwc_disp [
    {-0.03125, -0.01171875},
    {0.0859375, 0.0},
    {-0.00390625, 0.01953125},
    {-0.0234375, 0.0078125},
    {-0.01953125, -0.01171875},
    {-0.01953125, 0.00390625},
    {-0.01953125, -0.01953125}
  ]
  # grey cloud for cloudy
  @cgc_disp [
    {0.03515625, -0.01953125},
    {-0.0859375, 0.0},
    {0.00390625, 0.01953125},
    {0.0234375, 0.0078125},
    {0.01953125, -0.01171875},
    {0.01953125, 0.00390625},
    {0.01953125, -0.01953125}
  ]

  def draw_cloudy(buffer, {x, y}) do
    [{hx, hy} | t] = @cwc_disp
    white_cloud = [{hx + x, hy + y} | t]
    [{hx, hy} | t] = @cgc_disp
    gray_cloud = [{hx + x, hy + y} | t]

    buffer
    |> select_color(@color_white)
    |> append_bytes(@texture_yes_outline)
    |> draw(@cmd_set_poly_filled, white_cloud)
    # |> append_byte(@cmd_set_point_rel)
    |> append_bytes(@domain_new_pel)
    |> select_color(@color_gray)
    |> draw(@cmd_set_poly_filled, gray_cloud)
    |> append_byte(@cmd_set_point_rel)
    # |> append_bytes(@domain_no_outline)
    |> gcu_init()
  end

  # inner sun for partly cloudy
  @pis_disp [{-0.0078125, 0.02734375}, {-0.00390625, -0.046875}]

  # outer sun for partly cloudy
  @pos_disp [{-0.0078125, 0.01953125}, {-0.00390625, -0.03125}]

  # white cloud for partly cloudy
  @pwc_disp [
    {-0.046875, -0.02734375},
    {0.0859375, 0.0},
    {-0.00390625, 0.01953125},
    {-0.0234375, 0.0078125},
    {-0.01953125, -0.01171875},
    {-0.01953125, 0.00390625},
    {-0.01953125, -0.01953125}
  ]

  def draw_partly(buffer, {x, y}) do
    [{hx, hy} | t] = @pos_disp
    partly_outer_sun = [{hx + x, hy + y} | t]
    [{hx, hy} | t] = @pis_disp
    partly_inner_sun = [{hx + x, hy + y} | t]
    [{hx, hy} | t] = @pwc_disp
    white_cloud = [{hx + x, hy + y} | t]

    buffer
    |> select_color(@color_yellow)
    |> append_byte(@color_dark_green)
    |> draw(@cmd_set_arc_filled, partly_outer_sun)
    # |> append_byte(@cmd_set_point_rel)
    # |> append_bytes(@domain_new_pel)
    |> draw(@cmd_set_arc_outlined, partly_inner_sun)
    |> append_bytes(@texture_partly)
    |> select_color(@color_white)
    |> draw(@cmd_set_poly_filled, white_cloud)
    |> append_byte(@cmd_set_point_rel)
    # |> append_bytes(@domain_no_outline)
    |> gcu_init()
  end

  # lightning grey cloud
  @lgc_disp [
    {-0.04296875, 0.00390625},
    {0.0859375, 0.0},
    {-0.00390625, 0.01953125},
    {-0.0234375, 0.0078125},
    {-0.01953125, -0.01171875},
    {-0.01953125, 0.00390625}
  ]

  # lightning yellow dot - start
  @lyd_disp [{-0.03515625, -0.0234375}]

  # lightning yellow line - no disp
  @lyp_poly [{0.0234375, 0.0234375}, {0.0, -0.015625}, {0.01953125, 0.01953125}]

  def draw_lightning(buffer, {x, y}) do
    [{hx, hy} | t] = @lgc_disp
    ltg_gray_cloud = [{hx + x, hy + y} | t]
    [{hx, hy} | t] = @lyd_disp
    ltg_yellow_dot = [{hx + x, hy + y} | t]

    buffer
    |> append_bytes(@texture_partly)
    |> select_color(@color_gray)
    |> draw(@cmd_set_poly_filled, ltg_gray_cloud)
    |> select_color(@color_yellow)
    |> draw(@cmd_set_point_abs, ltg_yellow_dot)
    |> draw(@cmd_line_rel, @lyp_poly)
    |> gcu_init()
  end
end
