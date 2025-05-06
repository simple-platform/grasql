defmodule GraSQL.ColumnIntegrationTest do
  use ExUnit.Case, async: true
  alias GraSQL.Config
  alias GraSQL.Schema.{Relationship, Table}

  # Test resolver for integration tests
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
      %Table{schema: "public", name: "comments"}
    end

    @impl true
    def resolve_table("categories", _ctx) do
      %Table{schema: "public", name: "categories"}
    end

    @impl true
    def resolve_table("tags", _ctx) do
      %Table{schema: "public", name: "tags"}
    end

    @impl true
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

    @impl true
    def resolve_relationship("comments", %Table{name: "posts"}, _ctx) do
      %Relationship{
        source_table: %Table{schema: "public", name: "posts"},
        target_table: %Table{schema: "public", name: "comments"},
        source_columns: ["id"],
        target_columns: ["post_id"],
        type: :has_many,
        join_table: nil
      }
    end

    @impl true
    def resolve_relationship("categories", %Table{name: "posts"}, _ctx) do
      %Relationship{
        source_table: %Table{schema: "public", name: "posts"},
        target_table: %Table{schema: "public", name: "categories"},
        source_columns: ["id"],
        target_columns: ["id"],
        type: :many_to_many,
        join_table: %GraSQL.Schema.JoinTable{
          schema: "public",
          name: "post_categories",
          source_columns: ["post_id"],
          target_columns: ["category_id"]
        }
      }
    end

    @impl true
    def resolve_relationship("tags", %Table{name: "posts"}, _ctx) do
      %Relationship{
        source_table: %Table{schema: "public", name: "posts"},
        target_table: %Table{schema: "public", name: "tags"},
        source_columns: ["id"],
        target_columns: ["id"],
        type: :many_to_many,
        join_table: %GraSQL.Schema.JoinTable{
          schema: "public",
          name: "post_tags",
          source_columns: ["post_id"],
          target_columns: ["tag_id"]
        }
      }
    end

    @impl true
    def resolve_columns(%Table{name: "users"}, _ctx) do
      ["id", "username", "email", "password_hash", "created_at", "updated_at"]
    end

    @impl true
    def resolve_columns(%Table{name: "posts"}, _ctx) do
      ["id", "title", "content", "user_id", "published", "created_at", "updated_at"]
    end

    @impl true
    def resolve_columns(%Table{name: "comments"}, _ctx) do
      ["id", "content", "user_id", "post_id", "created_at", "updated_at"]
    end

    @impl true
    def resolve_columns(%Table{name: "categories"}, _ctx) do
      ["id", "name", "description", "created_at", "updated_at"]
    end

    @impl true
    def resolve_columns(%Table{name: "tags"}, _ctx) do
      ["id", "name", "created_at", "updated_at"]
    end

    @impl true
    def resolve_columns(%Table{}, _ctx) do
      ["id", "name", "created_at", "updated_at"]
    end

    @impl true
    def resolve_column_attribute(:sql_type, "id", _table, _ctx), do: "INTEGER"
    def resolve_column_attribute(:sql_type, "user_id", _table, _ctx), do: "INTEGER"
    def resolve_column_attribute(:sql_type, "post_id", _table, _ctx), do: "INTEGER"
    def resolve_column_attribute(:sql_type, "username", _table, _ctx), do: "VARCHAR(100)"
    def resolve_column_attribute(:sql_type, "email", _table, _ctx), do: "VARCHAR(255)"
    def resolve_column_attribute(:sql_type, "password_hash", _table, _ctx), do: "VARCHAR(255)"
    def resolve_column_attribute(:sql_type, "title", _table, _ctx), do: "VARCHAR(200)"
    def resolve_column_attribute(:sql_type, "content", _table, _ctx), do: "TEXT"
    def resolve_column_attribute(:sql_type, "description", _table, _ctx), do: "TEXT"
    def resolve_column_attribute(:sql_type, "name", _table, _ctx), do: "VARCHAR(100)"
    def resolve_column_attribute(:sql_type, "published", _table, _ctx), do: "BOOLEAN"
    def resolve_column_attribute(:sql_type, "created_at", _table, _ctx), do: "TIMESTAMP"
    def resolve_column_attribute(:sql_type, "updated_at", _table, _ctx), do: "TIMESTAMP"
    def resolve_column_attribute(:sql_type, _, _table, _ctx), do: "TEXT"

    @impl true
    def resolve_column_attribute(:default_value, "created_at", _table, _ctx),
      do: "CURRENT_TIMESTAMP"

    def resolve_column_attribute(:default_value, "updated_at", _table, _ctx),
      do: "CURRENT_TIMESTAMP"

    def resolve_column_attribute(:default_value, "published", _table, _ctx), do: "false"
    def resolve_column_attribute(:default_value, _, _table, _ctx), do: nil

    @impl true
    def resolve_typename(%Table{name: "users"}, _ctx), do: "User"
    def resolve_typename(%Table{name: "posts"}, _ctx), do: "Post"
    def resolve_typename(%Table{name: "comments"}, _ctx), do: "Comment"
    def resolve_typename(%Table{name: "categories"}, _ctx), do: "Category"
    def resolve_typename(%Table{name: "tags"}, _ctx), do: "Tag"
    def resolve_typename(%Table{}, _ctx), do: nil
  end

  # Helper functions for extracting data from schema
  defp get_table_from_schema(schema, path) do
    case schema[path] do
      {:table, %{table: table}} -> table
      _ -> nil
    end
  end

  defp get_relationship_from_schema(schema, path) do
    case schema[path] do
      {:relationship, relationship} -> relationship
      _ -> nil
    end
  end

  defp get_columns_from_schema(schema, path) do
    case schema[path] do
      {:table, %{columns: columns}} -> columns
      _ -> []
    end
  end

  describe "column resolution in integrated workflow" do
    setup do
      # Configure GraSQL to use our test resolver
      Application.put_env(:grasql, :schema_resolver, TestResolver)
      Application.put_env(:grasql, :__config__, %Config{schema_resolver: TestResolver})

      :ok
    end

    test "resolves columns for simple query operation" do
      # This test directly tests the schema resolution with a manually constructed resolution request
      # for a query operation, avoiding the need to mock the parser

      # Build a resolution request similar to what would be produced by parsing a users query
      resolution_request = {
        :field_names,
        ["users"],
        :field_paths,
        [[0]],
        :column_map,
        [{0, ["id", "username", "email"]}],
        :operation_kind,
        :query
      }

      # Resolve schema
      schema = GraSQL.Schema.resolve(resolution_request, TestResolver)

      # Check columns for users table
      users_columns = get_columns_from_schema(schema, ["users"])
      assert length(users_columns) > 0

      # Check specific columns
      column_names = Enum.map(users_columns, & &1.name)
      assert "id" in column_names
      assert "username" in column_names
      assert "email" in column_names

      # Check SQL types
      id_column = Enum.find(users_columns, &(&1.name == "id"))
      assert id_column.sql_type == "INTEGER"

      username_column = Enum.find(users_columns, &(&1.name == "username"))
      assert username_column.sql_type == "VARCHAR(100)"

      # In a query operation, default values should not be resolved
      assert id_column.default_value == nil
    end

    test "resolves columns for query with relationships" do
      # Build a resolution request that contains a relationship from users to posts
      resolution_request = {
        :field_names,
        ["users", "posts"],
        :field_paths,
        [[0], [0, 1]],
        :column_map,
        [
          {0, ["id", "username"]},
          {1, ["id", "title", "content"]}
        ],
        :operation_kind,
        :query
      }

      # Resolve schema
      schema = GraSQL.Schema.resolve(resolution_request, TestResolver)

      # Check that both users and posts tables are resolved
      users_table = get_table_from_schema(schema, ["users"])
      posts_relationship = get_relationship_from_schema(schema, ["users", "posts"])

      assert users_table != nil
      assert posts_relationship != nil

      # Check columns for users table
      users_columns = get_columns_from_schema(schema, ["users"])
      assert length(users_columns) > 0

      # Check that relationship target table is correctly set
      assert posts_relationship.target_table.name == "posts"

      # Verify that the relationship type is has_many
      assert posts_relationship.type == :has_many
    end

    test "resolves columns for insert mutation" do
      # Build a resolution request for an insert mutation
      resolution_request = {
        :field_names,
        ["users"],
        :field_paths,
        [[0]],
        :column_map,
        [{0, ["id", "username", "created_at"]}],
        :operation_kind,
        :insert_mutation
      }

      # Resolve schema
      schema = GraSQL.Schema.resolve(resolution_request, TestResolver)

      # Check operation kind is preserved
      assert schema[:operation_kind] == :insert_mutation

      # Check columns for users table
      users_columns = get_columns_from_schema(schema, ["users"])
      assert length(users_columns) > 0

      # For insert mutations, default values should be resolved
      created_at_column = Enum.find(users_columns, &(&1.name == "created_at"))
      assert created_at_column != nil
      assert created_at_column.default_value == "CURRENT_TIMESTAMP"
    end

    test "resolves columns for update mutation" do
      # Build a resolution request for an update mutation
      resolution_request = {
        :field_names,
        ["users"],
        :field_paths,
        [[0]],
        :column_map,
        [{0, ["id", "username", "updated_at"]}],
        :operation_kind,
        :update_mutation
      }

      # Resolve schema
      schema = GraSQL.Schema.resolve(resolution_request, TestResolver)

      # Check operation kind is preserved
      assert schema[:operation_kind] == :update_mutation

      # Check columns for users table
      users_columns = get_columns_from_schema(schema, ["users"])
      assert length(users_columns) > 0

      # For update mutations, default values should be resolved
      updated_at_column = Enum.find(users_columns, &(&1.name == "updated_at"))
      assert updated_at_column != nil
      assert updated_at_column.default_value == "CURRENT_TIMESTAMP"
    end

    test "resolves columns for delete mutation" do
      # Build a resolution request for a delete mutation
      resolution_request = {
        :field_names,
        ["users"],
        :field_paths,
        [[0]],
        :column_map,
        [{0, ["id", "username"]}],
        :operation_kind,
        :delete_mutation
      }

      # Resolve schema
      schema = GraSQL.Schema.resolve(resolution_request, TestResolver)

      # Check operation kind is preserved
      assert schema[:operation_kind] == :delete_mutation

      # Check columns for users table
      users_columns = get_columns_from_schema(schema, ["users"])
      assert length(users_columns) > 0

      # For delete mutations, only sql_type should be resolved
      id_column = Enum.find(users_columns, &(&1.name == "id"))
      assert id_column != nil
      assert id_column.sql_type == "INTEGER"
      assert id_column.default_value == nil
    end

    test "resolves deeply nested relationships with columns" do
      # Build a resolution request with deeply nested relationships
      resolution_request = {
        :field_names,
        ["users", "posts", "comments"],
        :field_paths,
        [[0], [0, 1], [0, 1, 2]],
        :column_map,
        [
          {0, ["id", "username"]},
          {1, ["id", "title"]},
          {2, ["id", "content"]}
        ],
        :operation_kind,
        :query
      }

      # Resolve schema
      schema = GraSQL.Schema.resolve(resolution_request, TestResolver)

      # Check that all relationships are resolved correctly
      users_table = get_table_from_schema(schema, ["users"])
      posts_relationship = get_relationship_from_schema(schema, ["users", "posts"])
      comments_relationship = get_relationship_from_schema(schema, ["users", "posts", "comments"])

      assert users_table != nil
      assert posts_relationship != nil
      assert comments_relationship != nil

      # Check relationship chain is correctly set up
      assert posts_relationship.source_table.name == "users"
      assert posts_relationship.target_table.name == "posts"
      assert comments_relationship.source_table.name == "posts"
      assert comments_relationship.target_table.name == "comments"

      # Check column data types for each level
      users_columns = get_columns_from_schema(schema, ["users"])
      assert Enum.find(users_columns, &(&1.name == "id")).sql_type == "INTEGER"
      assert Enum.find(users_columns, &(&1.name == "username")).sql_type == "VARCHAR(100)"
    end

    test "resolves complex relationships with different join types" do
      # Build a resolution request with multiple relationship types
      resolution_request = {
        :field_names,
        ["posts", "comments", "categories", "tags"],
        :field_paths,
        [[0], [0, 1], [0, 2], [0, 3]],
        :column_map,
        [
          {0, ["id", "title"]},
          {1, ["id", "content"]},
          {2, ["id", "name"]},
          {3, ["id", "name"]}
        ],
        :operation_kind,
        :query
      }

      # Resolve schema
      schema = GraSQL.Schema.resolve(resolution_request, TestResolver)

      # Check relationship types
      posts_comments = get_relationship_from_schema(schema, ["posts", "comments"])
      posts_categories = get_relationship_from_schema(schema, ["posts", "categories"])
      posts_tags = get_relationship_from_schema(schema, ["posts", "tags"])

      # Verify has_many relationship
      assert posts_comments.type == :has_many
      assert posts_comments.join_table == nil

      # Verify many_to_many relationships
      assert posts_categories.type == :many_to_many
      assert posts_categories.join_table != nil
      assert posts_categories.join_table.name == "post_categories"

      assert posts_tags.type == :many_to_many
      assert posts_tags.join_table != nil
      assert posts_tags.join_table.name == "post_tags"

      # Check column types
      posts_columns = get_columns_from_schema(schema, ["posts"])
      assert Enum.find(posts_columns, &(&1.name == "id")).sql_type == "INTEGER"
      assert Enum.find(posts_columns, &(&1.name == "title")).sql_type == "VARCHAR(200)"
    end
  end
end
