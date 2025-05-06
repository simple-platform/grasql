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

    @impl true
    def resolve_typename(%GraSQL.Schema.Table{name: "users_table"}, _context) do
      "User"  # Map "users_table" database table to "User" GraphQL type
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

  @doc """
  Returns a list of column names for a table.

  ## Parameters
    * `table` - The resolved database table
    * `context` - Optional context map with user/tenant information

  ## Returns
    A list of column names

  ## Example

  ```elixir
  def resolve_columns(%GraSQL.Schema.Table{name: "users"}, _context) do
    ["id", "username", "email", "created_at"]
  end
  ```
  """
  @callback resolve_columns(
              table :: GraSQL.Schema.Table.t(),
              context :: map()
            ) :: list(String.t())

  @doc """
  Resolves a specific attribute for a column.

  ## Parameters
    * `attribute` - The attribute to resolve (:sql_type, :default_value)
    * `column_name` - The name of the column
    * `table` - The resolved database table containing the column
    * `context` - Optional context map with user/tenant information

  ## Returns
    The resolved attribute value

  ## Example

  ```elixir
  def resolve_column_attribute(:sql_type, "id", %GraSQL.Schema.Table{name: "users"}, _context) do
    "INTEGER"
  end

  def resolve_column_attribute(:default_value, "created_at", %GraSQL.Schema.Table{name: "users"}, _context) do
    "CURRENT_TIMESTAMP"
  end
  ```
  """
  @callback resolve_column_attribute(
              attribute :: atom(),
              column_name :: String.t(),
              table :: GraSQL.Schema.Table.t(),
              context :: map()
            ) :: any()

  @doc """
  Resolves the GraphQL __typename for a database table.

  Determines what GraphQL type name should be used for a given database table.
  This is used to include the __typename field in GraphQL responses.

  ## Parameters

  * `table` - The resolved database table
  * `context` - Optional context map with user/tenant information

  ## Returns

  * A string representing the GraphQL type name, or nil to use the default naming

  ## Example

  ```elixir
  def resolve_typename(%GraSQL.Schema.Table{name: "users"}, _context) do
    "User"  # Map "users" table to "User" GraphQL type
  end

  # Fall back to default naming for other tables
  def resolve_typename(_table, _context), do: nil
  ```
  """
  @callback resolve_typename(
              table :: GraSQL.Schema.Table.t(),
              context :: map()
            ) :: String.t() | nil

  # Make resolve_typename an optional callback
  @optional_callbacks [resolve_typename: 2]

  defmacro __using__(_opts) do
    quote do
      @behaviour GraSQL.SchemaResolver
      # No default implementations - users must implement these
    end
  end
end
