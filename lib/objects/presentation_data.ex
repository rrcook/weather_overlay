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

defmodule PresentationData do

  defstruct [
    :segment_type,
    :segment_length,
    :pdt_type,
    :presentation_data
  ]

  @type t :: %__MODULE__{
    segment_type: ObjectTypes.segment_type(),
    segment_length: integer(),
    pdt_type: ObjectTypes.presentation_data_type(),
    presentation_data: binary()
  }

  @spec new() :: PresentationData.t()
  def new() do
    %PresentationData{segment_type: :presentation_data}
  end

  @spec new(ObjectTypes.presentation_data_type(), binary()) :: PresentationData.t()
  def new(presentation_data_type, data) do
    # size of "static data" is segment_type = 1, segment_length = 2, pdt_tye = 1

    segment_length = 4 + byte_size(data)

    %PresentationData{
      segment_type: :presentation_data,
      segment_length: segment_length,
      pdt_type: presentation_data_type,
      presentation_data: data
    }
  end

  defimpl ObjectEncoder, for: PresentationData do
    use ObjectConstants
    @spec encode(PresentationData.t()) :: <<_::32, _::_*8>>
    def encode(%PresentationData{} = pd_segment) do
      <<
        @segment_value_map[pd_segment.segment_type],
        pd_segment.segment_length::16-little,
        @presentation_data_type_value_map[pd_segment.pdt_type],
        pd_segment.presentation_data::binary
      >>
    end
  end
end
