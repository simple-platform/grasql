defmodule GraSQL.FieldTest do
  use ExUnit.Case
  doctest GraSQL.Field

  alias GraSQL.Field
  alias GraSQL.Selection
  alias GraSQL.SourcePosition

  test "new/5 creates a new field" do
    selection = Selection.new()
    pos = SourcePosition.new(5, 10)
    field = Field.new("users", "u", %{limit: 10}, selection, pos)

    assert field.name == "users"
    assert field.alias == "u"
    assert field.arguments == %{limit: 10}
    assert field.selection == selection
    assert field.source_position == pos
  end

  test "new_leaf/4 creates a field with an empty selection" do
    pos = SourcePosition.new(5, 10)
    field = Field.new_leaf("id", nil, %{}, pos)

    assert field.name == "id"
    assert field.alias == nil
    assert field.arguments == %{}
    assert %Selection{fields: []} = field.selection
    assert field.source_position == pos
  end

  test "effective_name/1 returns the alias if it exists" do
    field = %Field{name: "users", alias: "u"}
    assert Field.effective_name(field) == "u"
  end

  test "effective_name/1 returns the name if no alias exists" do
    field = %Field{name: "users", alias: nil}
    assert Field.effective_name(field) == "users"
  end

  test "get_argument/3 returns the argument value if it exists" do
    field = %Field{arguments: %{"limit" => 10}}
    assert Field.get_argument(field, "limit", 20) == 10
  end

  test "get_argument/3 returns the default value if the argument does not exist" do
    field = %Field{arguments: %{}}
    assert Field.get_argument(field, "limit", 20) == 20
  end
end
