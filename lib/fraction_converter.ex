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
