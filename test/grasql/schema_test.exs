defmodule GraSQL.SchemaTest do
  use ExUnit.Case, async: true

  alias GraSQL.Schema
  alias GraSQL.Schema.{JoinTable, Relationship, Table}

  # Define a test resolver for testing
  defmodule TestResolver do
    use GraSQL.SchemaResolver

    @impl true
    def resolve_table("users", _ctx) do
      %Table{schema: "public", name: "users"}
    end

    def resolve_table("posts", _ctx) do
      %Table{schema: "blog", name: "articles"}
    end

    def resolve_table("comments", _ctx) do
      %Table{schema: "blog", name: "comments"}
    end

    def resolve_table(field_name, _ctx) do
      %Table{schema: "public", name: field_name}
    end

    @impl true
    def resolve_relationship("posts", %Table{name: "users"} = users_table, _ctx) do
      %Relationship{
        type: :has_many,
        source_table: users_table,
        target_table: %Table{schema: "blog", name: "articles"},
        source_columns: ["id"],
        target_columns: ["user_id"],
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

    def resolve_relationship("categories", %Table{name: "articles"} = posts_table, _ctx) do
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
  end

  describe "resolve/3" do
    test "resolves a simple query with single table" do
      # Create a resolution request with users field
      resolution_request = {:field_names, ["users"], :field_paths, [[0]]}

      # Resolve schema
      schema = Schema.resolve(resolution_request, TestResolver)

      # Check resolved schema
      assert schema.tables != []
      assert Enum.empty?(schema.relationships)
      assert is_map(schema.path_map)

      # Check path map
      assert match?({:table, %Table{schema: "public", name: "users"}}, schema.path_map[["users"]])
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
      assert schema.tables != []
      assert schema.relationships != []
      assert is_map(schema.path_map)

      # Check path map - should have table and relationship entries
      assert match?({:table, %Table{schema: "public", name: "users"}}, schema.path_map[["users"]])
      assert match?({:relationship, %Relationship{}}, schema.path_map[["users", "posts"]])

      # Verify relationship is correct
      {:relationship, relationship} = schema.path_map[["users", "posts"]]
      assert relationship.type == :has_many
      assert relationship.source_table.name == "users"
      assert relationship.target_table.name == "articles"
      assert relationship.source_columns == ["id"]
      assert relationship.target_columns == ["user_id"]
      assert relationship.join_table == nil
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
      assert schema.tables != []
      assert schema.relationships != []
      assert is_map(schema.path_map)

      # Check path map - should have all entries
      assert match?({:table, %Table{schema: "public", name: "users"}}, schema.path_map[["users"]])
      assert match?({:relationship, %Relationship{}}, schema.path_map[["users", "posts"]])

      assert match?(
               {:relationship, %Relationship{}},
               schema.path_map[["users", "posts", "comments"]]
             )

      assert match?(
               {:relationship, %Relationship{}},
               schema.path_map[["users", "posts", "categories"]]
             )

      # Verify many-to-many relationship
      {:relationship, categories_rel} = schema.path_map[["users", "posts", "categories"]]
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
      end

      # Resolve schema with context
      schema = Schema.resolve(resolution_request, ContextTestResolver, context)

      # Verify context was passed to resolver
      {:table, table} = schema.path_map[["users"]]
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
end
