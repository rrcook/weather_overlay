defmodule Header do
  defstruct [
    :object_name,
    :object_ext,
    :sequence,
    :object_type,
    :object_module,
    :length,
    :candicacy_version_high,
    :num_objects,
    :candidacy_version_low,
    :object_list
  ]

  @type t :: %__MODULE__{
    object_name: binary(),
    object_ext: binary(),
    sequence: non_neg_integer(),
    object_type: ObjectTypes.object_type(),
    object_module: any(),
    length: non_neg_integer(),
    candicacy_version_high: non_neg_integer(),
    num_objects: non_neg_integer(),
    candidacy_version_low: non_neg_integer(),
    object_list: list(binary())
  }

  @spec new(binary(), binary(), ObjectTypes.object_type(), list(binary())) :: Header.t()
  def new(object_name, object_ext, object_type, object_list) do
    %Header{
      object_name: object_name,
      object_ext: object_ext,
      sequence: 1,
      object_type: object_type,
      object_module: nil,
      candicacy_version_high: 0,
      num_objects: length(object_list),
      candidacy_version_low: 1,
      object_list: object_list
    }
  end

  # The length of all the static parts of the header
  # name, ext, sequence, type, length, candicacy high, num objects, candicacy low

  defimpl ObjectEncoder, for: Header do
    use ObjectConstants
    @static_size 8 + 3 + 1 + 1 + 2 + 1 + 1 + 1

    def encode(%Header{} = header) do
      encoded_buffer =
        Enum.map(header.object_list, fn o -> ObjectEncoder.encode(o) end)
        |> IO.iodata_to_binary()

      header_length = @static_size + byte_size(encoded_buffer)

      <<
        header.object_name::binary-size(8),
        String.pad_trailing(header.object_ext, 3)::binary-size(3),
        header.sequence,
        @object_value_map[header.object_type],
        header_length::16-little,
        header.candicacy_version_high,
        header.num_objects,
        header.candidacy_version_low,
        encoded_buffer::binary
      >>
    end
  end
end
