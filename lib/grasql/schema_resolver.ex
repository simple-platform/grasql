defmodule GraSQL.SchemaResolver do
  @moduledoc """
  Behavior for resolving database schema information for GraSQL.

  This module defines callbacks for resolving tables and relationships
  that are used during the GraphQL to SQL compilation process.

  Implement this behavior to provide custom schema resolution for your database.
  The resolver is responsible for:

  * Providing table metadata (columns, primary keys, etc.)
  * Defining relationships between tables
  * Specifying join conditions for queries
  * Applying any database-specific customizations

  ## Implementation Example

  ```elixir
  defmodule MyApp.DatabaseResolver do
    @behaviour GraSQL.SchemaResolver

    @impl true
    def resolve_table(%{name: "users"} = table, _ctx) do
      Map.merge(table, %{
        schema: "public",
        columns: ["id", "name", "email", "created_at"],
        primary_key: ["id"]
      })
    end

    @impl true
    def resolve_relationship(%{from_table: "users", to_table: "posts"} = rel, _ctx) do
      Map.merge(rel, %{
        join_type: :left_outer,
        join_conditions: [{"users.id", "posts.user_id"}]
      })
    end
  end
  ```
  """

  @type context :: %{optional(atom() | String.t()) => any()}

  @doc """
  Resolves table information for multiple tables in the query structure tree (QST).

  This is called by GraSQL during the compilation phase to enrich the query
  with database schema information.

  Note: This is a placeholder implementation that will be fully implemented in a future release.
  Currently, it does not modify the query structure tree.

  ## Parameters
    * `qst` - The query structure tree
    * `ctx` - Context map for custom information

  ## Returns
    * The enriched query structure tree
  """
  def resolve_tables(qst, _ctx) do
    # This is a placeholder implementation that will be completed in a future release.
    # It will call resolve_table/2 for each table in the query structure tree.
    qst
  end

  @doc """
  Resolves relationship information for the query structure tree (QST).

  This is called by GraSQL during the compilation phase to add relationship
  information to the query.

  Note: This is a placeholder implementation that will be fully implemented in a future release.
  Currently, it does not modify the query structure tree.

  ## Parameters
    * `qst` - The query structure tree
    * `ctx` - Context map for custom information

  ## Returns
    * The enriched query structure tree with relationship information
  """
  def resolve_relationships(qst, _ctx) do
    # This is a placeholder implementation that will be completed in a future release.
    # It will call resolve_relationship/2 for each relationship in the query structure tree.
    qst
  end

  @doc """
  Callback for resolving a single table's metadata.

  Implement this function to provide database-specific information for a table.
  The implementation should enrich the table map with metadata needed for SQL generation.

  ## Parameters
    * `table` - The table information map, which includes at minimum:
      * `name` - The table name as referred to in the GraphQL query

    * `ctx` - Context map for custom information, which may include:
      * Database connection
      * Schema information
      * Tenant identifiers
      * Any other custom data needed for resolution

  ## Returns
    * An updated table information map with resolved metadata, which should include:
      * `schema` - Database schema name (optional)
      * `columns` - List of column names
      * `primary_key` - List of primary key column names
      * Any additional metadata required by your implementation
  """
  @callback resolve_table(table :: map(), ctx :: context()) :: map()

  @doc """
  Callback for resolving a relationship between tables.

  Implement this function to provide information about foreign keys and join conditions.
  The implementation should specify how tables are related for SQL join operations.

  ## Parameters
    * `relationship` - The relationship information map, which includes at minimum:
      * `from_table` - The source table name
      * `to_table` - The target table name
      * `field_name` - The GraphQL field name representing this relationship

    * `ctx` - Context map for custom information, which may include:
      * Database connection
      * Schema information
      * Tenant identifiers
      * Any other custom data needed for resolution

  ## Returns
    * An updated relationship information map with resolved metadata, which should include:
      * `join_type` - The type of SQL join (e.g., `:inner`, `:left_outer`)
      * `join_conditions` - List of column pairs for the join condition, where each pair is
        a tuple of `{from_column, to_column}` or a string containing a SQL condition
      * Any additional metadata required by your implementation
  """
  @callback resolve_relationship(relationship :: map(), ctx :: context()) :: map()
end
