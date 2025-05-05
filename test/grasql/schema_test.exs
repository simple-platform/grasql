defmodule GraSQL.SchemaTest do
  use ExUnit.Case, async: true
  doctest GraSQL.Schema

  alias GraSQL.Schema
  alias GraSQL.Schema.{JoinTable, Relationship, Table}

  # Define a test resolver for testing
  defmodule TestResolver do
    @behaviour GraSQL.SchemaResolver

    @impl true
    def resolve_table("users", _ctx) do
      %Table{schema: "public", name: "users"}
    end

    @impl true
    def resolve_table("posts", _ctx) do
      %Table{schema: "public", name: "posts"}
    end

    @impl true
    def resolve_table("comments", _ctx) do
      %Table{schema: "blog", name: "comments"}
    end

    def resolve_table(field_name, _ctx) do
      %Table{schema: "public", name: field_name}
    end

    @impl true
    def resolve_relationship("posts", %Table{name: "users"}, _ctx) do
      %Relationship{
        source_table: %Table{schema: "public", name: "users"},
        target_table: %Table{schema: "public", name: "posts"},
        source_columns: ["id"],
        target_columns: ["user_id"],
        type: :has_many,
        join_table: nil
      }
    end

    def resolve_relationship("comments", %Table{name: "articles"} = posts_table, _ctx) do
      %Relationship{
        type: :has_many,
        source_table: posts_table,
        target_table: %Table{schema: "blog", name: "comments"},
        source_columns: ["id"],
        target_columns: ["article_id"],
        join_table: nil
      }
    end

    def resolve_relationship("categories", %Table{name: "posts"} = posts_table, _ctx) do
      %Relationship{
        type: :many_to_many,
        source_table: posts_table,
        target_table: %Table{schema: "blog", name: "categories"},
        source_columns: ["id"],
        target_columns: ["id"],
        join_table: %JoinTable{
          schema: "blog",
          name: "article_categories",
          source_columns: ["article_id"],
          target_columns: ["category_id"]
        }
      }
    end

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
    def resolve_typename(%Table{name: "users"}, _ctx), do: "User"
    def resolve_typename(%Table{name: "posts"}, _ctx), do: "Post"

    def resolve_typename(%Table{name: "comments"}, _ctx) do
      "Comment"
    end

    def resolve_typename(%Table{name: name}, _ctx) do
      String.capitalize(name)
    end

    @impl true
    def resolve_columns(%Table{name: "users"}, _ctx) do
      ["id", "username", "email", "created_at"]
    end

    @impl true
    def resolve_columns(%Table{name: "posts"}, _ctx) do
      ["id", "title", "content", "user_id", "published", "created_at"]
    end

    @impl true
    def resolve_column_attribute(:sql_type, "id", %Table{name: "users"}, _ctx), do: "INTEGER"

    def resolve_column_attribute(:sql_type, "username", %Table{name: "users"}, _ctx),
      do: "VARCHAR(100)"

    def resolve_column_attribute(:sql_type, "email", %Table{name: "users"}, _ctx),
      do: "VARCHAR(255)"

    def resolve_column_attribute(:sql_type, "created_at", %Table{name: "users"}, _ctx),
      do: "TIMESTAMP"

    def resolve_column_attribute(:sql_type, "id", %Table{name: "posts"}, _ctx), do: "INTEGER"

    def resolve_column_attribute(:sql_type, "title", %Table{name: "posts"}, _ctx),
      do: "VARCHAR(200)"

    def resolve_column_attribute(:sql_type, "content", %Table{name: "posts"}, _ctx), do: "TEXT"
    def resolve_column_attribute(:sql_type, "user_id", %Table{name: "posts"}, _ctx), do: "INTEGER"

    def resolve_column_attribute(:sql_type, "published", %Table{name: "posts"}, _ctx),
      do: "BOOLEAN"

    def resolve_column_attribute(:sql_type, "created_at", %Table{name: "posts"}, _ctx),
      do: "TIMESTAMP"

    def resolve_column_attribute(:default_value, "id", %Table{name: "users"}, _ctx), do: nil
    def resolve_column_attribute(:default_value, "username", %Table{name: "users"}, _ctx), do: nil
    def resolve_column_attribute(:default_value, "email", %Table{name: "users"}, _ctx), do: nil

    def resolve_column_attribute(:default_value, "created_at", %Table{name: "users"}, _ctx),
      do: "CURRENT_TIMESTAMP"

    def resolve_column_attribute(:default_value, "id", %Table{name: "posts"}, _ctx), do: nil
    def resolve_column_attribute(:default_value, "title", %Table{name: "posts"}, _ctx), do: nil
    def resolve_column_attribute(:default_value, "content", %Table{name: "posts"}, _ctx), do: nil
    def resolve_column_attribute(:default_value, "user_id", %Table{name: "posts"}, _ctx), do: nil

    def resolve_column_attribute(:default_value, "published", %Table{name: "posts"}, _ctx),
      do: "false"

    def resolve_column_attribute(:default_value, "created_at", %Table{name: "posts"}, _ctx),
      do: "CURRENT_TIMESTAMP"
  end

  # Helper functions for extracting data from the new schema format
  defp get_tables(schema) do
    schema
    |> Enum.filter(fn {_path, entry} -> match?({:table, _}, entry) end)
    |> Enum.map(fn {_path, {:table, %{table: table}}} -> table end)
  end

  defp get_relationships(schema) do
    schema
    |> Enum.filter(fn {_path, entry} -> match?({:relationship, _}, entry) end)
    |> Enum.map(fn {_path, {:relationship, relationship}} -> relationship end)
  end

  defp get_columns(schema, table_name) do
    schema
    |> Enum.find(fn {[name], _} -> name == table_name end)
    |> case do
      {_, {:table, %{columns: columns}}} -> columns
      _ -> []
    end
  end

  describe "typename resolution" do
    test "adds __typename to root tables" do
      # Create a resolution request with users field
      resolution_request = {:field_names, ["users"], :field_paths, [[0]]}

      # Resolve schema
      schema = Schema.resolve(resolution_request, TestResolver)

      # Get the users table from the schema
      {:table, %{table: users_table}} = schema[["users"]]

      # Check typename
      assert users_table.__typename == "User"
    end

    test "adds __typename to target tables in relationships" do
      # Create a resolution request with users and posts fields
      resolution_request = {
        :field_names,
        ["users", "posts"],
        :field_paths,
        [[0], [0, 1]]
      }

      # Resolve schema
      schema = Schema.resolve(resolution_request, TestResolver)

      # Check schema - should have typename in relationship's target table
      {:relationship, relationship} = schema[["users", "posts"]]
      assert relationship.target_table.__typename == "Post"
    end

    test "adds __typename to deeply nested tables" do
      # Create a resolution request with deeply nested relationships
      resolution_request = {
        :field_names,
        ["users", "posts", "comments"],
        :field_paths,
        [[0], [0, 1], [0, 1, 2]]
      }

      # Resolve schema
      schema = Schema.resolve(resolution_request, TestResolver)

      # Check nested relationship target table typename
      {:relationship, comments_rel} = schema[["users", "posts", "comments"]]
      assert comments_rel.target_table.__typename == "Comment"
    end
  end

  describe "resolve/3" do
    test "resolves a simple query with single table" do
      # Create a resolution request with users field
      resolution_request = {:field_names, ["users"], :field_paths, [[0]]}

      # Resolve schema
      schema = Schema.resolve(resolution_request, TestResolver)

      # Check resolved schema
      tables = get_tables(schema)
      relationships = get_relationships(schema)

      assert length(tables) == 1
      assert Enum.empty?(relationships)
      assert is_map(schema)

      # Check schema
      assert match?(
               {:table, %{table: %Table{schema: "public", name: "users"}}},
               schema[["users"]]
             )
    end

    test "resolves a query with relationships" do
      # Create a resolution request with users and posts fields
      resolution_request = {
        :field_names,
        ["users", "posts"],
        :field_paths,
        [[0], [0, 1]]
      }

      # Resolve schema
      schema = Schema.resolve(resolution_request, TestResolver)

      # Check resolved schema
      tables = get_tables(schema)
      relationships = get_relationships(schema)

      assert length(tables) == 2
      assert length(relationships) == 1
      assert is_map(schema)

      # Check schema - should have table and relationship entries
      assert match?(
               {:table, %{table: %Table{schema: "public", name: "users"}}},
               schema[["users"]]
             )

      assert match?({:relationship, %Relationship{}}, schema[["users", "posts"]])

      # Verify relationship is correct
      {:relationship, relationship} = schema[["users", "posts"]]
      assert relationship.type == :has_many
      assert relationship.source_table.name == "users"
      assert relationship.target_table.name == "posts"
      assert relationship.source_columns == ["id"]
      assert relationship.target_columns == ["user_id"]
      assert relationship.join_table == nil

      # Verify target tables are included in the result
      target_table_included =
        Enum.any?(tables, fn table ->
          table.name == "posts" && table.schema == "public"
        end)

      assert target_table_included, "Target table should be included in the tables list"
    end

    test "resolves a query with multiple nested relationships" do
      # Create a resolution request with deeply nested relationships
      resolution_request = {
        :field_names,
        ["users", "posts", "comments", "categories"],
        :field_paths,
        [[0], [0, 1], [0, 1, 2], [0, 1, 3]]
      }

      # Resolve schema
      schema = Schema.resolve(resolution_request, TestResolver)

      # Check resolved schema
      tables = get_tables(schema)
      relationships = get_relationships(schema)

      assert length(tables) == 4
      assert length(relationships) == 3
      assert is_map(schema)

      # Check schema - should have all entries
      assert match?(
               {:table, %{table: %Table{schema: "public", name: "users"}}},
               schema[["users"]]
             )

      assert match?({:relationship, %Relationship{}}, schema[["users", "posts"]])

      assert match?(
               {:relationship, %Relationship{}},
               schema[["users", "posts", "comments"]]
             )

      assert match?(
               {:relationship, %Relationship{}},
               schema[["users", "posts", "categories"]]
             )

      # Verify many-to-many relationship
      {:relationship, categories_rel} = schema[["users", "posts", "categories"]]
      assert categories_rel.type == :many_to_many
      assert categories_rel.join_table.name == "article_categories"
    end

    test "handles context passing" do
      # Create a simple resolution request
      resolution_request = {:field_names, ["users"], :field_paths, [[0]]}

      # Create a test context with some values
      context = %{tenant_id: "tenant123", user_id: 456}

      # Create a context-checking resolver
      defmodule ContextTestResolver do
        use GraSQL.SchemaResolver

        @impl true
        def resolve_table("users", ctx) do
          # Store the context in the table name for testing
          tenant = ctx[:tenant_id] || "none"
          %Table{schema: "public", name: "users_#{tenant}"}
        end

        @impl true
        def resolve_relationship(_field_name, parent_table, _ctx) do
          %Relationship{
            type: :has_many,
            source_table: parent_table,
            target_table: %Table{schema: "public", name: "default"},
            source_columns: ["id"],
            target_columns: ["parent_id"],
            join_table: nil
          }
        end

        @impl true
        def resolve_columns(_table, _ctx) do
          ["id", "name"]
        end

        @impl true
        def resolve_column_attribute(:sql_type, _column, _table, _ctx) do
          "TEXT"
        end

        def resolve_column_attribute(:default_value, _column, _table, _ctx) do
          nil
        end
      end

      # Resolve schema with context
      schema = Schema.resolve(resolution_request, ContextTestResolver, context)

      # Verify context was passed to resolver
      {:table, %{table: table}} = schema[["users"]]
      assert table.name == "users_tenant123"
    end
  end

  describe "data structures" do
    test "Table struct" do
      table = %Table{schema: "public", name: "users"}
      assert table.schema == "public"
      assert table.name == "users"
    end

    test "JoinTable struct" do
      join_table = %JoinTable{
        schema: "public",
        name: "post_categories",
        source_columns: ["post_id"],
        target_columns: ["category_id"]
      }

      assert join_table.schema == "public"
      assert join_table.name == "post_categories"
      assert join_table.source_columns == ["post_id"]
      assert join_table.target_columns == ["category_id"]
    end

    test "Relationship struct" do
      source_table = %Table{schema: "public", name: "users"}
      target_table = %Table{schema: "public", name: "posts"}

      relationship = %Relationship{
        source_table: source_table,
        target_table: target_table,
        source_columns: ["id"],
        target_columns: ["user_id"],
        type: :has_many,
        join_table: nil
      }

      assert relationship.source_table == source_table
      assert relationship.target_table == target_table
      assert relationship.source_columns == ["id"]
      assert relationship.target_columns == ["user_id"]
      assert relationship.type == :has_many
      assert relationship.join_table == nil
    end
  end

  test "resolves schema with a simple field path" do
    resolution_request = %{
      field_names: ["users"],
      field_paths: [["users"]]
    }

    schema = Schema.resolve(resolution_request, TestResolver)
    tables = get_tables(schema)

    assert length(tables) == 1
    assert Enum.empty?(get_relationships(schema))

    [table] = tables
    assert table.name == "users"
    assert table.schema == "public"
    assert table.__typename == "User"
  end

  test "resolves schema with a nested field path" do
    resolution_request = %{
      field_names: ["users", "posts"],
      field_paths: [["users"], ["users", "posts"]]
    }

    schema = Schema.resolve(resolution_request, TestResolver)

    tables = get_tables(schema)
    relationships = get_relationships(schema)

    assert length(tables) == 2
    assert length(relationships) == 1

    [rel] = relationships
    assert rel.source_table.name == "users"
    assert rel.target_table.name == "posts"
    assert rel.source_columns == ["id"]
    assert rel.target_columns == ["user_id"]
    assert rel.type == :has_many
  end

  test "resolves schema with columns and operation kind" do
    # For this test, we'll use the 8-element tuple format as defined in extract_resolution_info
    resolution_request = {
      :field_names,
      ["users", "posts"],
      :field_paths,
      [[0], [0, 1]],
      :column_map,
      [{0, ["id", "username"]}, {1, ["title", "published"]}],
      :operation_kind,
      :insert_mutation
    }

    schema = Schema.resolve(resolution_request, TestResolver)

    tables = get_tables(schema)
    relationships = get_relationships(schema)

    assert length(tables) == 2
    assert length(relationships) == 1

    # Check columns for users table
    users_columns = get_columns(schema, "users")
    assert length(users_columns) == 2

    # Check column attributes for users table
    id_column = Enum.find(users_columns, fn col -> col.name == "id" end)
    assert id_column.sql_type == "INTEGER"
    assert id_column.default_value == nil

    username_column = Enum.find(users_columns, fn col -> col.name == "username" end)
    assert username_column.sql_type == "VARCHAR(100)"
    assert username_column.default_value == nil

    # Check columns for posts table
    posts_columns = get_columns(schema, "posts")
    assert length(posts_columns) == 2

    # Check column attributes for posts table
    title_column = Enum.find(posts_columns, fn col -> col.name == "title" end)
    assert title_column.sql_type == "VARCHAR(200)"
    assert title_column.default_value == nil

    published_column = Enum.find(posts_columns, fn col -> col.name == "published" end)
    assert published_column.sql_type == "BOOLEAN"
    assert published_column.default_value == "false"
  end
end
