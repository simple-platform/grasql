defmodule GraSQL.ResultStructureTest do
  use ExUnit.Case
  doctest GraSQL.ResultStructure

  alias GraSQL.ResultStructure

  test "new/0 creates an empty result structure" do
    structure = ResultStructure.new()
    assert structure.fields == []
    assert structure.nested_objects == %{}
  end

  test "new/2 creates a result structure with fields and nested objects" do
    fields = [%{sql_column: "id", path: ["id"], is_json: false}]
    nested = %{["user"] => ["u_"]}
    structure = ResultStructure.new(fields, nested)

    assert structure.fields == fields
    assert structure.nested_objects == nested
  end

  test "add_field/4 adds a field to the result structure" do
    structure = ResultStructure.new()
    updated = ResultStructure.add_field(structure, "u_id", ["user", "id"], false)
    updated = ResultStructure.add_field(updated, "u_name", ["user", "name"], false)

    assert Enum.count(updated.fields) == 2
    assert Enum.any?(updated.fields, &(&1.sql_column == "u_id" and &1.path == ["user", "id"]))
    assert Enum.any?(updated.fields, &(&1.sql_column == "u_name" and &1.path == ["user", "name"]))
  end

  test "add_nested_object/3 adds a nested object mapping" do
    structure = ResultStructure.new()
    updated = ResultStructure.add_nested_object(structure, ["user"], "u_")

    assert updated.nested_objects == %{["user"] => ["u_"]}
  end

  test "add_nested_object/3 appends to existing prefixes" do
    structure = %ResultStructure{nested_objects: %{["user"] => ["u_"]}}
    updated = ResultStructure.add_nested_object(structure, ["user"], "user_")

    assert updated.nested_objects == %{["user"] => ["u_", "user_"]}
  end

  test "get_fields_for_path/2 returns fields that match the given path" do
    fields = [
      %{sql_column: "u_id", path: ["user", "id"], is_json: false},
      %{sql_column: "u_name", path: ["user", "name"], is_json: false},
      %{sql_column: "p_id", path: ["post", "id"], is_json: false}
    ]

    structure = ResultStructure.new(fields, %{})

    user_fields = ResultStructure.get_fields_for_path(structure, ["user"])
    assert length(user_fields) == 2
    assert Enum.any?(user_fields, &(&1.sql_column == "u_id"))
    assert Enum.any?(user_fields, &(&1.sql_column == "u_name"))

    post_fields = ResultStructure.get_fields_for_path(structure, ["post"])
    assert length(post_fields) == 1
    assert Enum.any?(post_fields, &(&1.sql_column == "p_id"))
  end
end
