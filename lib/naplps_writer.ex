defmodule NaplpsWriter do

  @moduledoc """
  Documentation for `NaplpsWriter`.
  """


  use NaplpsConstants

  # Many commands and operands are single bytes, no calculation
  # What is happening will be obvious from the byte passed in
  def append_byte(buffer, byte), do: buffer <> << byte >>

  defp prepend_sign(number, char_list) do
    cond do
      number < 0 -> [?1 | char_list]
      true -> [?0 | char_list]
    end
  end

  defp char_to_bit(?1), do: 1
  defp char_to_bit(_), do: 0

  defp mb_buildxy(buffer, xys) when is_list(xys) and length(xys) < 3 do
    buffer
  end

  defp mb_buildxy(buffer, xys) do
    [{xbit1, ybit1}, {xbit2, ybit2}, {xbit3, ybit3} | rest] = xys

    xybyte = <<0b11::2, xbit1::1, xbit2::1, xbit3::1, ybit1::1, ybit2::1, ybit3::1>>
    mb_buildxy(buffer <> xybyte, rest)
  end

  def mb_xy_old(buffer, {x, y}) do
    x_frac = Enum.map(prepend_sign(x, to_charlist(FractionConverter.decimal_to_binary_fraction(x))), &char_to_bit/1)
    y_frac = Enum.map(prepend_sign(y, to_charlist(FractionConverter.decimal_to_binary_fraction(y))), &char_to_bit/1)

    buffer <> mb_buildxy(<<>>, Enum.zip(x_frac, y_frac))
  end

  def make_bits(fraction) do
    bitfrac = FractionConverter.decimal_to_binary_fraction(fraction)

    bitstext = cond do
      fraction < 0 ->
        {bnum, _remainder} = Integer.parse(bitfrac, 2)
        bcomp = (bnot(bnum) + 1) &&& 0xff
        Integer.to_string(bcomp, 2)
      true ->
        bitfrac
    end

    Enum.map(prepend_sign(fraction, to_charlist(bitstext)), &char_to_bit/1)

  end

  def mb_xy(buffer, xys ) when is_list(xys) do
    pts_buffer = Enum.map(xys, fn xy -> mb_xy(<<>>, xy) end)

    buffer <> Enum.reduce(pts_buffer, <<>>, &(&2 <> &1))
  end

  def mb_xy(buffer, {x, y}) do
    x_frac = make_bits(x)
    y_frac = make_bits(y)

    buffer <> mb_buildxy(<<>>, Enum.zip(x_frac, y_frac))
  end

  def gcu_init(), do: gcu_init(<<>>)

  def gcu_init(buffer) do

    init_buffer = <<
      @cmd_domain,
      0xC8>>              # 2 dimensions on points, multivalue operands is 3 bytes,
                         # single value operand is one byte
      <>
      mb_xy(<<>>, {1 / 256, 1 / 256}) # pixel width/height of 1/1, in muli-byte format
      <>
      <<
      @cmd_texture_attr,
      0xC0,              # Solid Fill, don't draw outline of fills, solid line
      0xC0, 0xD2, 0xC0,
      @cmd_shift_in
    >>

    buffer <> init_buffer
  end

  def select_color(buffer, color) do
    buffer <> <<@cmd_select_color, color>>
  end

  def draw(buffer, command, points) when is_list(points) do
    buffer
    |> append_byte(command)
    |> mb_xy(points)

  end

  def draw(buffer, command, point) do
    draw(buffer, command, [ point ])
  end

  def draw_text_raw(buffer, text) do
    buffer <> text
  end

  def draw_text_abs(buffer, text, point), do: draw_text(buffer, @cmd_set_point_abs, text, point)

  def draw_text_rel(buffer, text, point), do: draw_text(buffer, @cmd_set_point_rel, text, point)

  defp draw_text(buffer, command, text, point) do
    buffer
    |> draw(command, point)
    |> draw_text_raw(text)
  end

  def text_attributes(buffer, point) do
    text_size_buffer = mb_xy(<<>>, point)
    # mvp at the moment - assume default rotation, cursor etc.
    # Proportional spacing, same as used in Prodigy
    default_text_buffer = <<@cmd_text_attr, 0xF0, 0xC0>>
    buffer <> default_text_buffer <> text_size_buffer
  end

end
