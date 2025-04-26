defmodule GraSQL.SourcePositionTest do
  use ExUnit.Case
  doctest GraSQL.SourcePosition

  alias GraSQL.SourcePosition

  test "new/2 creates a new source position" do
    pos = SourcePosition.new(10, 5)
    assert pos.line == 10
    assert pos.column == 5
  end

  test "compare/2 returns :lt when first position is before second" do
    pos1 = SourcePosition.new(10, 5)
    pos2 = SourcePosition.new(10, 20)
    assert SourcePosition.compare(pos1, pos2) == :lt

    pos1 = SourcePosition.new(5, 10)
    pos2 = SourcePosition.new(10, 5)
    assert SourcePosition.compare(pos1, pos2) == :lt
  end

  test "compare/2 returns :gt when first position is after second" do
    pos1 = SourcePosition.new(10, 20)
    pos2 = SourcePosition.new(10, 5)
    assert SourcePosition.compare(pos1, pos2) == :gt

    pos1 = SourcePosition.new(15, 5)
    pos2 = SourcePosition.new(10, 20)
    assert SourcePosition.compare(pos1, pos2) == :gt
  end

  test "compare/2 returns :eq when positions are equal" do
    pos1 = SourcePosition.new(10, 5)
    pos2 = SourcePosition.new(10, 5)
    assert SourcePosition.compare(pos1, pos2) == :eq
  end
end
