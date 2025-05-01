defmodule GraSQL.SimpleResolver do
  @moduledoc """
  A simple implementation of the GraSQL.SchemaResolver behaviour for use in doctests.
  This resolver simply returns the input values without transformation.
  """

  @behaviour GraSQL.SchemaResolver

  def resolve_table(table, _ctx), do: table

  def resolve_relationship(rel, _ctx), do: rel
end
