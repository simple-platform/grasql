defmodule GraSQLTest do
  use ExUnit.Case
  doctest GraSQL

  test "greets the world" do
    assert GraSQL.hello() == :world
  end
end
