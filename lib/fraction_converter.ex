defmodule FractionConverter do
  def decimal_to_binary_fraction(decimal_frac, precision \\ 8) do
    decimal_to_binary_fraction(abs(decimal_frac), precision, "")
  end

  defp decimal_to_binary_fraction(_, 0, binary_frac), do: binary_frac

  defp decimal_to_binary_fraction(decimal_frac, precision, binary_frac) do
    decimal_frac = decimal_frac * 2
    if decimal_frac >= 1.0 do
      decimal_to_binary_fraction(decimal_frac - 1.0, precision - 1, "#{binary_frac}1")
    else
      decimal_to_binary_fraction(decimal_frac, precision - 1, "#{binary_frac}0")
    end
  end
end
