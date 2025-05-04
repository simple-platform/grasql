defmodule GraSQL.SchemaResolverTest do
  use ExUnit.Case, async: true

  alias GraSQL.Schema.{JoinTable, Relationship, Table}

  # Define a custom test resolver
  defmodule CustomResolver do
    use GraSQL.SchemaResolver

    @impl true
    def resolve_table("users", _ctx) do
      %Table{
        schema: "custom_schema",
        name: "custom_users"
      }
    end

    def resolve_table(field_name, ctx) do
      # Use context to determine schema
      schema = Map.get(ctx, :schema, "public")

      %Table{
        schema: schema,
        name: field_name
      }
    end

    @impl true
    def resolve_relationship("posts", %Table{name: "custom_users"}, _ctx) do
      %Relationship{
        type: :has_many,
        source_table: %Table{schema: "custom_schema", name: "custom_users"},
        target_table: %Table{schema: "custom_schema", name: "custom_posts"},
        source_columns: ["user_id"],
        target_columns: ["id"],
        join_table: nil
      }
    end

    def resolve_relationship("categories", %Table{name: "custom_posts"}, _ctx) do
      %Relationship{
        type: :many_to_many,
        source_table: %Table{schema: "custom_schema", name: "custom_posts"},
        target_table: %Table{schema: "custom_schema", name: "custom_categories"},
        source_columns: ["id"],
        target_columns: ["id"],
        join_table: %JoinTable{
          schema: "custom_schema",
          name: "custom_post_categories",
          source_columns: ["post_id"],
          target_columns: ["category_id"]
        }
      }
    end

    def resolve_relationship(field_name, parent_table, _ctx) do
      %Relationship{
        type: :belongs_to,
        source_table: parent_table,
        target_table: %Table{schema: parent_table.schema, name: field_name},
        source_columns: ["#{field_name}_id"],
        target_columns: ["id"],
        join_table: nil
      }
    end
  end

  describe "custom schema resolver" do
    test "resolve_table/2 handles custom table names" do
      table = CustomResolver.resolve_table("users", %{})

      assert %Table{} = table
      assert table.schema == "custom_schema"
      assert table.name == "custom_users"
    end

    test "resolve_table/2 uses context values" do
      table = CustomResolver.resolve_table("posts", %{schema: "test_schema"})

      assert %Table{} = table
      assert table.schema == "test_schema"
      assert table.name == "posts"
    end

    test "resolve_relationship/3 handles custom relationships" do
      source_table = %Table{schema: "custom_schema", name: "custom_users"}
      relationship = CustomResolver.resolve_relationship("posts", source_table, %{})

      assert %Relationship{} = relationship
      assert relationship.type == :has_many
      assert relationship.source_table.name == "custom_users"
      assert relationship.target_table.name == "custom_posts"
      assert relationship.source_columns == ["user_id"]
      assert relationship.target_columns == ["id"]
    end

    test "resolve_relationship/3 handles many-to-many relationships" do
      source_table = %Table{schema: "custom_schema", name: "custom_posts"}
      relationship = CustomResolver.resolve_relationship("categories", source_table, %{})

      assert %Relationship{} = relationship
      assert relationship.type == :many_to_many
      assert relationship.source_table.name == "custom_posts"
      assert relationship.target_table.name == "custom_categories"
      assert relationship.join_table != nil
      assert relationship.join_table.name == "custom_post_categories"
      assert relationship.join_table.source_columns == ["post_id"]
      assert relationship.join_table.target_columns == ["category_id"]
    end

    test "resolve_relationship/3 falls back to default implementation" do
      source_table = %Table{schema: "custom_schema", name: "some_table"}
      relationship = CustomResolver.resolve_relationship("author", source_table, %{})

      assert %Relationship{} = relationship
      assert relationship.type == :belongs_to
      assert relationship.source_table.name == "some_table"
      assert relationship.target_table.name == "author"
      assert relationship.source_columns == ["author_id"]
      assert relationship.target_columns == ["id"]
    end
  end

  describe "built-in resolvers" do
    test "SimpleResolver implements SchemaResolver behavior" do
      # Verify SimpleResolver implements required callbacks
      assert function_exported?(GraSQL.SimpleResolver, :resolve_table, 2)
      assert function_exported?(GraSQL.SimpleResolver, :resolve_relationship, 3)

      # Test basic functionality
      table = GraSQL.SimpleResolver.resolve_table("users", %{})
      assert %Table{} = table
      assert table.schema == "public"
      assert table.name == "users"

      relationship = GraSQL.SimpleResolver.resolve_relationship("posts", table, %{})
      assert %Relationship{} = relationship
      assert relationship.type == :has_many
    end
  end

  describe "behavior verification" do
    test "using macro adds behaviour" do
      # Use the SchemaResolver behavior
      defmodule TestResolver do
        use GraSQL.SchemaResolver

        @impl true
        def resolve_table(_field_name, _ctx), do: %Table{schema: "test", name: "test"}

        @impl true
        def resolve_relationship(_field_name, _parent_table, _ctx) do
          %Relationship{
            type: :has_one,
            source_table: %Table{schema: "test", name: "test"},
            target_table: %Table{schema: "test", name: "test"},
            source_columns: ["id"],
            target_columns: ["id"],
            join_table: nil
          }
        end
      end

      # Verify behavior was added
      behaviours = TestResolver.__info__(:attributes)[:behaviour]
      assert Enum.member?(behaviours, GraSQL.SchemaResolver)
    end
  end
end
