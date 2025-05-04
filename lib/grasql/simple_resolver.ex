defmodule GraSQL.SimpleResolver do
  @moduledoc """
  Default implementation of the GraSQL.SchemaResolver behavior.

  This module provides simple implementations of the required callbacks
  for schema resolution. It's designed for quick setup and testing,
  not for production use.

  The resolver uses these simple conventions:
  * GraphQL field names map directly to table names
  * Tables are assumed to be in the "public" schema
  * Relationships use "id" as the source column
  * Target tables use "{parent_table_name}_id" as the foreign key

  For production use, implement your own resolver that provides
  actual database schema information.
  """

  use GraSQL.SchemaResolver

  @impl true
  @doc """
  Resolves a GraphQL field to a database table.

  Maps field names directly to table names in the public schema.

  ## Parameters

  * `field_name` - The GraphQL field name to resolve
  * `_ctx` - Ignored context parameter

  ## Returns

  * A table struct with schema "public" and name matching the field_name

  ## Examples

      iex> GraSQL.SimpleResolver.resolve_table("users", %{})
      %GraSQL.Schema.Table{schema: "public", name: "users"}
  """
  @spec resolve_table(String.t(), map()) :: GraSQL.Schema.Table.t()
  def resolve_table(field_name, _ctx) do
    # Simple passthrough implementation that assumes field_name is table name
    %GraSQL.Schema.Table{
      schema: "public",
      name: field_name
    }
  end

  @impl true
  @doc """
  Resolves a GraphQL relationship field to a database relationship.

  Assumes a has_many relationship where the target table has
  a foreign key named "{parent_table.name}_id".

  ## Parameters

  * `field_name` - The relationship field name to resolve
  * `parent_table` - The parent table in the relationship
  * `_ctx` - Ignored context parameter

  ## Returns

  * A has_many relationship struct connecting the parent table to the target table

  ## Examples

      iex> parent = %GraSQL.Schema.Table{schema: "public", name: "users"}
      iex> GraSQL.SimpleResolver.resolve_relationship("posts", parent, %{})
      %GraSQL.Schema.Relationship{
        source_table: %GraSQL.Schema.Table{schema: "public", name: "users"},
        target_table: %GraSQL.Schema.Table{schema: "public", name: "posts"},
        source_columns: ["id"],
        target_columns: ["users_id"],
        type: :has_many,
        join_table: nil
      }
  """
  @spec resolve_relationship(String.t(), GraSQL.Schema.Table.t(), map()) ::
          GraSQL.Schema.Relationship.t()
  def resolve_relationship(field_name, parent_table, _ctx) do
    # Simple implementation that assumes basic relationship structure
    %GraSQL.Schema.Relationship{
      source_table: parent_table,
      target_table: %GraSQL.Schema.Table{
        schema: "public",
        name: field_name
      },
      source_columns: ["id"],
      target_columns: ["#{parent_table.name}_id"],
      type: :has_many,
      join_table: nil
    }
  end
end
