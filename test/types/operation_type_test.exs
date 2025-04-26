defmodule GraSQL.OperationTypeTest do
  use ExUnit.Case
  doctest GraSQL.OperationType

  alias GraSQL.OperationType

  test "query/0 returns :query atom" do
    assert OperationType.query() == :query
  end

  test "mutation/0 returns :mutation atom" do
    assert OperationType.mutation() == :mutation
  end

  test "@type t includes query and mutation" do
    # Type checking is done at compile time, this is just to verify the type exists
    query_val = OperationType.query()
    mutation_val = OperationType.mutation()

    # Simple check to ensure the values are atoms
    assert is_atom(query_val)
    assert is_atom(mutation_val)
  end
end
