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

defmodule ObjectTypes do
  @type object_type ::
          :page_format_object
          | :page_template_object
          | :page_element_object
          | :program_object
          | :window_object

  @type segment_type ::
          :program_call
          | :field_level_program_call
          | :field_definition
          | :custom_text
          | :custom_cursor
          | :page_element_selector
          | :page_element_call
          | :page_format_call
          | :partition_definition
          | :presentation_data
          | :embedded_object
          | :program_data
          | :keyword_navigation

  @type presentation_data_type ::
          :presentation_data_naplps
          | :presentation_data_ascii
end
