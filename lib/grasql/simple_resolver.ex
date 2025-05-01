defmodule GraSQL.SimpleResolver do
  @moduledoc """
  Default implementation of the GraSQL.SchemaResolver behavior.

  This module provides basic implementations of the required callbacks
  for schema resolution in GraSQL. It's designed as a fallback resolver
  when no custom resolver is configured.

  For production use, you should implement your own resolver that provides
  actual database schema information.
  """

  @behaviour GraSQL.SchemaResolver

  @impl true
  def resolve_table(table, _ctx) do
    # Simple passthrough implementation that returns the table as-is
    # In a real implementation, this would add schema, columns, primary keys, etc.
    table
  end

  @impl true
  def resolve_relationship(relationship, _ctx) do
    # Simple passthrough implementation that returns the relationship as-is
    # In a real implementation, this would add join types, conditions, etc.
    relationship
  end
end
