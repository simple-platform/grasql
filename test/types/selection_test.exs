defmodule GraSQL.SelectionTest do
  use ExUnit.Case
  doctest GraSQL.Selection

  alias GraSQL.Field
  alias GraSQL.Selection

  test "new/0 creates an empty selection" do
    selection = Selection.new()
    assert selection.fields == []
  end

  test "new/1 creates a selection with fields" do
    fields = [%Field{name: "id"}]
    selection = Selection.new(fields)

    assert selection.fields == fields
  end

  test "add_field/2 adds a field to the selection" do
    selection = Selection.new()
    field = %Field{name: "id"}
    updated = Selection.add_field(selection, field)

    assert [^field] = updated.fields
  end

  test "find_field/2 returns the field with the given name if it exists" do
    field1 = %Field{name: "id"}
    field2 = %Field{name: "name"}
    selection = Selection.new([field1, field2])

    assert {:ok, ^field1} = Selection.find_field(selection, "id")
    assert {:ok, ^field2} = Selection.find_field(selection, "name")
  end

  test "find_field/2 returns :error if the field does not exist" do
    selection = Selection.new()
    assert Selection.find_field(selection, "missing") == :error
  end
end
