defmodule NaplpsWriterTest do
  use ExUnit.Case
  doctest NaplpsWriter

  test "greets the world" do
    assert NaplpsWriter.hello() == :world
  end
end
