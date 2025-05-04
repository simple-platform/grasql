defmodule GraSQL.SchemaResolver do
  @moduledoc """
  Behavior for resolving GraphQL fields to database tables and relationships.

  This behavior defines the contract for mapping GraphQL fields to your database schema.
  Implement this behavior to customize how GraSQL translates field names to tables,
  columns, and relationships.

  ## Example Implementation

  ```elixir
  defmodule MyApp.CustomResolver do
    use GraSQL.SchemaResolver

    @impl true
    def resolve_table("users", _context) do
      %GraSQL.Schema.Table{
        schema: "public",
        name: "users_table"  # Map "users" GraphQL field to "users_table"
      }
    end

    @impl true
    def resolve_relationship("posts", parent_table, _context) do
      %GraSQL.Schema.Relationship{
        source_table: parent_table,
        target_table: %GraSQL.Schema.Table{schema: "public", name: "posts"},
        source_columns: ["id"],
        target_columns: ["user_id"],
        type: :has_many,
        join_table: nil
      }
    end
  end
  """

  @doc """
  Resolves a GraphQL field to a database table.

  Determines which database table should be queried for a given GraphQL field.

  ## Parameters

  * `field_name` - The name of the GraphQL field
  * `context` - Optional context map with user/tenant information

  ## Returns

  * A `GraSQL.Schema.Table` struct representing the resolved table

  ## Example

  ```elixir
  def resolve_table("users", _context) do
    %GraSQL.Schema.Table{
      schema: "app_schema",
      name: "users"
    }
  end
  ```
  """
  @callback resolve_table(field_name :: String.t(), context :: map()) :: GraSQL.Schema.Table.t()

  @doc """
  Resolves a GraphQL relationship field to a database relationship.

  Determines how a field relates to its parent table in the database.

  ## Parameters

  * `field_name` - The name of the GraphQL relationship field
  * `parent_table` - The resolved parent table
  * `context` - Optional context map with user/tenant information

  ## Returns

  * A `GraSQL.Schema.Relationship` struct representing the resolved relationship

  ## Example

  ```elixir
  def resolve_relationship("comments", parent_table, _context) do
    %GraSQL.Schema.Relationship{
      source_table: parent_table,
      target_table: %GraSQL.Schema.Table{schema: "public", name: "comments"},
      source_columns: ["id"],
      target_columns: ["post_id"],
      type: :has_many,
      join_table: nil
    }
  end
  ```
  """
  @callback resolve_relationship(
              field_name :: String.t(),
              parent_table :: GraSQL.Schema.Table.t(),
              context :: map()
            ) :: GraSQL.Schema.Relationship.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour GraSQL.SchemaResolver
      # No default implementations - users must implement these
    end
  end
end
