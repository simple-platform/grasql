defmodule GraSQL.ColumnTest do
  use ExUnit.Case, async: true
  alias GraSQL.Schema.Column

  describe "Column struct" do
    test "creates a column with valid attributes" do
      column = %Column{name: "id", sql_type: "INTEGER", default_value: nil}
      assert column.name == "id"
      assert column.sql_type == "INTEGER"
      assert column.default_value == nil
    end

    test "accepts various SQL types" do
      # Test with different SQL types
      types = [
        "INTEGER",
        "VARCHAR(255)",
        "TEXT",
        "TIMESTAMP",
        "BOOLEAN",
        "JSONB",
        "UUID",
        "DECIMAL(10,2)"
      ]

      Enum.each(types, fn sql_type ->
        column = %Column{name: "test", sql_type: sql_type, default_value: nil}
        assert column.sql_type == sql_type
      end)
    end

    test "allows various default values" do
      # Test with different default values
      defaults = [
        nil,
        "CURRENT_TIMESTAMP",
        "0",
        "''",
        "true",
        "false",
        "42",
        "DEFAULT",
        "NULL"
      ]

      Enum.each(defaults, fn default_value ->
        column = %Column{name: "test", sql_type: "TEXT", default_value: default_value}
        assert column.default_value == default_value
      end)
    end

    test "supports pattern matching on fields" do
      column = %Column{name: "id", sql_type: "INTEGER", default_value: nil}

      # Test pattern matching on individual fields
      assert %Column{name: "id"} = column
      assert %Column{sql_type: "INTEGER"} = column
      assert %Column{default_value: nil} = column

      # Test pattern matching on multiple fields
      assert %Column{name: "id", sql_type: "INTEGER"} = column
      assert %Column{name: "id", default_value: nil} = column
      assert %Column{sql_type: "INTEGER", default_value: nil} = column

      # Test with variable binding
      %Column{name: name, sql_type: sql_type, default_value: default_value} = column
      assert name == "id"
      assert sql_type == "INTEGER"
      assert default_value == nil
    end

    test "supports creating a column from a map" do
      # Create a column from a map
      map = %{name: "id", sql_type: "INTEGER", default_value: nil}
      column = struct(Column, map)

      assert column.name == "id"
      assert column.sql_type == "INTEGER"
      assert column.default_value == nil
    end

    test "supports creating a column from a keyword list" do
      # Create a column from a keyword list
      keyword_list = [name: "id", sql_type: "INTEGER", default_value: nil]
      column = struct(Column, keyword_list)

      assert column.name == "id"
      assert column.sql_type == "INTEGER"
      assert column.default_value == nil
    end

    test "uses default values for unspecified fields" do
      # Create with partial specification
      column = %Column{name: "id"}

      # Check that unspecified fields get default values
      assert column.name == "id"
      assert column.sql_type == nil
      assert column.default_value == nil
    end

    test "can be compared for equality" do
      col1 = %Column{name: "id", sql_type: "INTEGER", default_value: nil}
      col2 = %Column{name: "id", sql_type: "INTEGER", default_value: nil}
      col3 = %Column{name: "name", sql_type: "VARCHAR(255)", default_value: nil}

      # Same data should be equal
      assert col1 == col2

      # Different data should not be equal
      refute col1 == col3
    end

    test "can be part of a collection" do
      col1 = %Column{name: "id", sql_type: "INTEGER", default_value: nil}
      col2 = %Column{name: "name", sql_type: "VARCHAR(255)", default_value: nil}
      col3 = %Column{name: "email", sql_type: "VARCHAR(255)", default_value: nil}

      # Create a list of columns
      columns = [col1, col2, col3]

      # Test operations on the collection
      assert length(columns) == 3
      assert Enum.find(columns, &(&1.name == "id")) != nil
      assert Enum.map(columns, & &1.name) == ["id", "name", "email"]
      assert Enum.filter(columns, &(&1.sql_type == "VARCHAR(255)")) == [col2, col3]
    end

    test "supports updating fields" do
      column = %Column{name: "id", sql_type: "INTEGER", default_value: nil}

      # Update individual fields
      updated = %Column{column | sql_type: "BIGINT"}
      assert updated.name == "id"
      assert updated.sql_type == "BIGINT"
      assert updated.default_value == nil

      # Update multiple fields
      updated = %Column{column | sql_type: "SERIAL", default_value: "1"}
      assert updated.name == "id"
      assert updated.sql_type == "SERIAL"
      assert updated.default_value == "1"
    end

    test "supports transformations with map/reduce" do
      columns = [
        %Column{name: "id", sql_type: "INTEGER", default_value: nil},
        %Column{name: "name", sql_type: "VARCHAR(255)", default_value: nil},
        %Column{name: "created_at", sql_type: "TIMESTAMP", default_value: "CURRENT_TIMESTAMP"}
      ]

      # Test map operation
      column_names = Enum.map(columns, & &1.name)
      assert column_names == ["id", "name", "created_at"]

      # Test filter operation
      text_columns = Enum.filter(columns, &String.contains?(&1.sql_type, "VARCHAR"))
      assert length(text_columns) == 1
      assert hd(text_columns).name == "name"

      # Test reduce operation
      has_default =
        Enum.reduce(columns, false, fn col, acc ->
          acc || col.default_value != nil
        end)

      assert has_default == true
    end

    test "supports conversion to map" do
      column = %Column{name: "id", sql_type: "INTEGER", default_value: nil}
      map = Map.from_struct(column)

      assert map == %{name: "id", sql_type: "INTEGER", default_value: nil}
    end

    test "supports conversion to keyword list" do
      column = %Column{name: "id", sql_type: "INTEGER", default_value: nil}

      # Convert to keyword list
      keyword_list =
        column
        |> Map.from_struct()
        |> Enum.into([])

      assert Keyword.get(keyword_list, :name) == "id"
      assert Keyword.get(keyword_list, :sql_type) == "INTEGER"
      assert Keyword.get(keyword_list, :default_value) == nil
    end

    test "supports string interpolation" do
      column = %Column{name: "id", sql_type: "INTEGER", default_value: nil}

      # Test basic interpolation
      string = "Column: #{inspect(column)}"
      assert is_binary(string)
      assert String.contains?(string, "id")
      assert String.contains?(string, "INTEGER")
    end

    test "works with List functions" do
      columns = [
        %Column{name: "id", sql_type: "INTEGER", default_value: nil},
        %Column{name: "name", sql_type: "VARCHAR(255)", default_value: nil},
        %Column{name: "email", sql_type: "VARCHAR(255)", default_value: nil}
      ]

      # Test sorting
      sorted = Enum.sort_by(columns, & &1.name)
      assert Enum.map(sorted, & &1.name) == ["email", "id", "name"]

      # Test grouping
      grouped = Enum.group_by(columns, & &1.sql_type)
      assert map_size(grouped) == 2
      assert length(grouped["INTEGER"]) == 1
      assert length(grouped["VARCHAR(255)"]) == 2
    end
  end
end
