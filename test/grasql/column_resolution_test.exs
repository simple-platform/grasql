defmodule GraSQL.ColumnResolutionTest do
  use ExUnit.Case, async: true
  alias GraSQL.Schema
  alias GraSQL.Schema.{Relationship, Table}

  # Test resolver with configurable behavior for testing column resolution
  defmodule TestResolver do
    @behaviour GraSQL.SchemaResolver

    @impl true
    def resolve_table(field_name, _ctx) do
      %Table{schema: "public", name: field_name}
    end

    @impl true
    def resolve_relationship(field_name, parent_table, _ctx) do
      %Relationship{
        type: :has_many,
        source_table: parent_table,
        target_table: %Table{schema: "public", name: field_name},
        source_columns: ["id"],
        target_columns: ["#{parent_table.name}_id"],
        join_table: nil
      }
    end

    @impl true
    def resolve_columns(%Table{name: table_name}, _ctx) do
      # Return different columns based on table name
      case table_name do
        "users" -> ["id", "name", "email", "created_at"]
        "posts" -> ["id", "title", "content", "user_id", "created_at"]
        "large_table" -> Enum.map(1..20, &"column_#{&1}")
        _ -> ["id", "name"]
      end
    end

    @impl true
    def resolve_column_attribute(attribute, column_name, %Table{name: _table_name}, _ctx) do
      case attribute do
        :sql_type -> resolve_sql_type(column_name)
        :default_value -> resolve_default_value(column_name)
        _ -> nil
      end
    end

    defp resolve_sql_type(column_name) do
      case column_name do
        "id" -> "INTEGER"
        col when col in ["name", "title", "email"] -> "VARCHAR(255)"
        "content" -> "TEXT"
        col when col in ["user_id", "post_id"] -> "INTEGER"
        "created_at" -> "TIMESTAMP"
        _ -> "TEXT"
      end
    end

    defp resolve_default_value(column_name) do
      case column_name do
        "id" -> nil
        "created_at" -> "CURRENT_TIMESTAMP"
        _ -> nil
      end
    end

    @impl true
    def resolve_typename(%Table{}, _ctx), do: nil
  end

  # Helper functions to extract data from the schema
  defp get_columns(schema, table_name) do
    schema
    |> Enum.find(fn
      {[^table_name], _} -> true
      _ -> false
    end)
    |> case do
      {_, {:table, %{columns: columns}}} -> columns
      _ -> []
    end
  end

  describe "column resolution" do
    test "resolves columns for single table" do
      # Create a resolution request with users table and specific columns
      resolution_request = {
        :field_names,
        ["users"],
        :field_paths,
        [[0]],
        :column_map,
        [{0, ["id", "name", "email"]}],
        :operation_kind,
        :query
      }

      # Directly pass the TestResolver to Schema.resolve
      schema = Schema.resolve(resolution_request, TestResolver)

      # Verify columns were resolved for users table
      columns = get_columns(schema, "users")
      assert length(columns) == 3

      # Verify we have the right columns with correct attributes
      column_names = Enum.map(columns, & &1.name)
      assert "id" in column_names
      assert "name" in column_names
      assert "email" in column_names

      # Check that sql_type was resolved for all columns
      Enum.each(columns, fn column ->
        assert column.sql_type != nil
      end)

      # For query operations, default values should not be resolved
      id_column = Enum.find(columns, &(&1.name == "id"))
      assert id_column.default_value == nil
    end

    test "resolves different attributes based on operation kind" do
      # Test with insert mutation (should resolve sql_type AND default_value)
      resolution_request = {
        :field_names,
        ["users"],
        :field_paths,
        [[0]],
        :column_map,
        [{0, ["id", "name", "created_at"]}],
        :operation_kind,
        :insert_mutation
      }

      schema = Schema.resolve(resolution_request, TestResolver)

      # Verify columns were resolved for users table
      columns = get_columns(schema, "users")
      assert length(columns) == 3

      # Verify default values were resolved
      created_at_column = Enum.find(columns, &(&1.name == "created_at"))
      assert created_at_column.default_value == "CURRENT_TIMESTAMP"

      # Verify each column has correct SQL type
      id_column = Enum.find(columns, &(&1.name == "id"))
      assert id_column.sql_type == "INTEGER"

      name_column = Enum.find(columns, &(&1.name == "name"))
      assert name_column.sql_type == "VARCHAR(255)"

      assert created_at_column.sql_type == "TIMESTAMP"
    end

    test "handles empty column maps" do
      # Test with no columns specified
      resolution_request = {
        :field_names,
        ["users"],
        :field_paths,
        [[0]],
        :column_map,
        [],
        :operation_kind,
        :query
      }

      schema = Schema.resolve(resolution_request, TestResolver)

      # Verify no columns were resolved for users table
      columns = get_columns(schema, "users")
      assert columns == []
    end

    test "handles tables with no specified columns" do
      # Test with table not in column map
      resolution_request = {
        :field_names,
        ["users", "posts"],
        :field_paths,
        [[0], [0, 1]],
        :column_map,
        # Only specify columns for users
        [{0, ["id", "name"]}],
        :operation_kind,
        :query
      }

      schema = Schema.resolve(resolution_request, TestResolver)

      # Verify columns were resolved for users but not posts
      users_columns = get_columns(schema, "users")
      posts_columns = get_columns(schema, "posts")

      assert length(users_columns) == 2
      assert posts_columns == []
    end

    test "uses sequential resolution for few columns" do
      # Test with a small number of columns
      resolution_request = {
        :field_names,
        ["users"],
        :field_paths,
        [[0]],
        :column_map,
        [{0, ["id", "name"]}],
        :operation_kind,
        :query
      }

      schema = Schema.resolve(resolution_request, TestResolver)

      # Verify columns were resolved
      columns = get_columns(schema, "users")
      assert length(columns) == 2

      # Verify column attributes
      id_column = Enum.find(columns, &(&1.name == "id"))
      assert id_column.sql_type == "INTEGER"

      name_column = Enum.find(columns, &(&1.name == "name"))
      assert name_column.sql_type == "VARCHAR(255)"
    end

    test "uses parallel resolution for many columns" do
      # Test with many columns to trigger parallel resolution
      resolution_request = {
        :field_names,
        ["large_table"],
        :field_paths,
        [[0]],
        :column_map,
        [{0, Enum.map(1..15, &"column_#{&1}")}],
        :operation_kind,
        :insert_mutation
      }

      schema = Schema.resolve(resolution_request, TestResolver)

      # Verify columns were resolved
      columns = get_columns(schema, "large_table")
      assert length(columns) == 15

      # Verify all column names are present
      column_names = Enum.map(columns, & &1.name)

      Enum.each(1..15, fn i ->
        assert "column_#{i}" in column_names
      end)

      # Verify sql_type and default_value are set for all columns
      Enum.each(columns, fn column ->
        assert column.sql_type == "TEXT"
        assert column.default_value == nil
      end)
    end

    test "handles nonexistent columns" do
      # Test with columns that don't exist in the table
      resolution_request = {
        :field_names,
        ["users"],
        :field_paths,
        [[0]],
        :column_map,
        [{0, ["id", "nonexistent_column"]}],
        :operation_kind,
        :query
      }

      schema = Schema.resolve(resolution_request, TestResolver)

      # Verify only existing columns were resolved
      columns = get_columns(schema, "users")
      assert length(columns) == 1
      assert hd(columns).name == "id"
    end

    test "passes context to resolver callbacks" do
      # Test resolver that verifies context is passed
      defmodule ContextTestResolver do
        @behaviour GraSQL.SchemaResolver

        # Add an Agent to track calls
        def start_agent do
          # Start a process to track what context was seen
          Agent.start_link(fn -> nil end, name: __MODULE__)
        end

        def get_last_context do
          Agent.get(__MODULE__, fn state -> state end)
        end

        @impl true
        def resolve_table(field_name, ctx) do
          # Store the context we received
          Agent.update(__MODULE__, fn _ -> ctx end)
          %Table{schema: "public", name: field_name}
        end

        @impl true
        def resolve_relationship(_field_name, _parent_table, _ctx), do: nil

        @impl true
        def resolve_columns(_table, _ctx), do: ["id"]

        @impl true
        def resolve_column_attribute(:sql_type, _column_name, _table, _ctx), do: "TEXT"
        def resolve_column_attribute(:default_value, _column_name, _table, _ctx), do: nil

        @impl true
        def resolve_typename(_table, _ctx), do: nil
      end

      # Start the tracking agent
      ContextTestResolver.start_agent()

      # Test with context values
      context = %{tenant_id: "tenant123", user_id: 456}

      resolution_request = {
        :field_names,
        ["users"],
        :field_paths,
        [[0]],
        :column_map,
        [{0, ["id"]}],
        :operation_kind,
        :query
      }

      # Call the schema resolver with our context
      Schema.resolve(resolution_request, ContextTestResolver, context)

      # Verify that the context was passed to our resolver
      assert ContextTestResolver.get_last_context() == context
    end
  end
end
