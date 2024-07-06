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

defmodule ObjectConstants do
  defmacro __using__(_) do
    quote do
      @value_object_map %{
        0x00 => :page_format_object,
        0x04 => :page_template_object,
        0x08 => :page_element_object,
        0x0C => :program_object,
        0x0E => :window_object
      }

      @object_value_map Map.new(@value_object_map, fn {key, val} -> {val, key} end)

      @value_segment_map %{
        0x01 => :program_call,
        0x02 => :field_level_program_call,
        0x04 => :field_definition,
        0x0A => :custom_text,
        0x0B => :custom_cursor,
        0x20 => :page_element_selector,
        0x21 => :page_element_call,
        0x31 => :page_format_call,
        0x33 => :partition_definition,
        0x51 => :presentation_data,
        0x52 => :embedded_object,
        0x61 => :program_data,
        0x71 => :keyword_navigation
      }

      @segment_value_map Map.new(@value_segment_map, fn {key, val} -> {val, key} end)

      @value_presentation_data_type_map %{
        0x01 => :presentation_data_naplps,
        0x02 => :presentation_data_ascii
      }

      @presentation_data_type_value_map Map.new(@value_presentation_data_type_map, fn {key, val} -> {val, key} end)

      ##### Functions that might find a home later

      # Puts the length of the buffer inside the buffer, at the offset.
      # Currently assumes 16-little
      defp inject_length(_buffer, _offset) do
        0
      end

    end
  end
end
