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
