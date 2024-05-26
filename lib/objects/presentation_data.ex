defmodule PresentationData do

  defstruct [
    :segment_type,
    :segment_length,
    :pdt_type,
    :presentation_data
  ]

  def new() do
    %PresentationData{segment_type: :presentation_data}
  end

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
