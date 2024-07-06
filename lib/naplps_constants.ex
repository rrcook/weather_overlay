# Copyright 2024, Ralph Richard Cook
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

defmodule NaplpsConstants do
  defmacro __using__(_) do
    quote do

      import Bitwise

      @b1              0x01
      @b2              0x02
      @b3              0x04
      @b4              0x08
      @b5              0x10
      @b6              0x20
      @b7              0x40
      @b8              0x80

      @operator_bit    0x40

      # The PDI primitives are as follows:
      @cmd_reset  @b8 ||| 0x20 # RESET - selective reset
      @cmd_domain  @b8 ||| 0x21 # DOMAIN - sets graphical environment
      @cmd_text_attr  @b8 ||| 0x22 # TEXT - sets default text attributes
      @cmd_texture_attr  @b8 ||| 0x23 # TEXTURE - sets line and fill patterns

      @cmd_set_point_abs  @b8 ||| 0x24 # POINT SET ABS
      @cmd_set_point_rel  @b8 ||| 0x25 # POINT SET REL
      @cmd_point_abs  @b8 ||| 0x26 # POINT ABS
      @cmd_point_rel  @b8 ||| 0x27 # POINT REL

      # Lines and Polylines
      @cmd_line_abs  @b8 ||| 0x28 # LINE ABS
      @cmd_line_rel  @b8 ||| 0x29 # LINE REL
      @cmd_set_line_abs  @b8 ||| 0x2A # SET & LINE ABS
      @cmd_set_line_rel  @b8 ||| 0x2B # SET & LINE REL

      # Arcs, Circles, Splines
      @cmd_arc_outlined  @b8 ||| 0x2C # ARC OUTLINED
      @cmd_arc_filled  @b8 ||| 0x2D # ARC FILLED
      @cmd_set_arc_outlined  @b8 ||| 0x2E # SET & ARC OUTLINED
      @cmd_set_arc_filled  @b8 ||| 0x2F # SET & ARC FILLED

      # Rectangles and histograms
      @cmd_rect_outlined  @b8 ||| 0x30 # RECT OUTLINED
      @cmd_rect_filled  @b8 ||| 0x31 # RECT FILLED
      @cmd_set_rect_outlined  @b8 ||| 0x32 # SET & RECT OUTLINED
      @cmd_set_rect_filled  @b8 ||| 0x33 # SET & RECT FILLED

      # Polygons
      @cmd_poly_outlined  @b8 ||| 0x34 # POLY OUTLINED - polyline
      @cmd_poly_filled  @b8 ||| 0x35 # POLY FILLED - polgon
      @cmd_set_poly_outlined  @b8 ||| 0x36 # SET & POLY OUTLINED - polyline
      @cmd_set_poly_filled  @b8 ||| 0x37 # SET & POLY FILLED - polygon

      @cmd_field  @b8 ||| 0x38 # FIELD - define bitmap field or input field
      @cmd_incremental_point  @b8 ||| 0x39 # INCREMENTAL POINT - color bitmap
      @cmd_incremental_line  @b8 ||| 0x3A # INCREMENTAL LINE - scribble
      @cmd_incremental_poly_filled  @b8 ||| 0x3B # INCREMENTAL POLY FILLED - filled scribble

      @cmd_set_color  @b8 ||| 0x3C # SET COLOR - specify an RGB color
      @cmd_wait  @b8 ||| 0x3D # WAIT - timed pause
      @cmd_select_color  @b8 ||| 0x3E # SELECT COLOR - set @cmd_  color mode
      @cmd_blink  @b8 ||| 0x3F # BLINK - palette animation

      @cmd_shift_in     0x0f
      @cmd_shift_out    0x0e

      #From the GCU/Prodigy palette
      @color_black           0xC0
      @color_red             0xC4
      @color_dark_gray       0xC8
      @color_blue            0xCC
      @color_gray            0xD0
      @color_brown           0xD4
      @color_dark_green      0xD8
      @color_white           0xDC
      @color_purple_blue     0xE0
      @color_dark_magenta    0xE4
      @color_magenta         0xE8
      @color_orange          0xEC
      @color_yellow          0xF0
      @color_green           0xF4
      @color_cyan            0xF8
      @color_dark_cyan       0xFC

      @hatching_solid        0xC0
      @hatching_vertical     0xC8

    end
  end
end
