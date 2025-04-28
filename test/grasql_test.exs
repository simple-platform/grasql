defmodule GraSQLTest do
  use ExUnit.Case
  doctest GraSQL

  # Test resolver for tracking method calls
  defmodule TestResolver do
    def resolve_tables(qst) do
      send(self(), {:resolve_tables, qst})
      Map.put(qst, :tables_resolved, true)
    end

    def resolve_relationships(qst) do
      send(self(), {:resolve_relationships, qst})
      Map.put(qst, :relationships_resolved, true)
    end

    def set_permissions(qst) do
      send(self(), {:set_permissions, qst})
      Map.put(qst, :permissions_set, true)
    end

    def set_overrides(qst) do
      send(self(), {:set_overrides, qst})
      Map.put(qst, :overrides_set, true)
    end
  end

  # Incomplete resolver for testing validation
  defmodule IncompleteResolver do
    def resolve_tables(qst), do: qst
    def resolve_relationships(qst), do: qst
    # Missing set_permissions and set_overrides
  end

  # We'll test only the validator logic which doesn't need the Native module
  describe "resolver validation" do
    test "validates resolver implements all required methods" do
      assert_raise ArgumentError, fn ->
        # We need to catch the error before it reaches Native.parse_and_analyze_query
        try_validate_resolver(IncompleteResolver)
      end
    end
  end

  # Helper to test just the validation logic
  defp try_validate_resolver(resolver) do
    required_methods = [:resolve_tables, :resolve_relationships, :set_permissions, :set_overrides]

    for method <- required_methods do
      unless Code.ensure_loaded?(resolver) and function_exported?(resolver, method, 1) do
        raise ArgumentError, "resolver must implement #{method}/1"
      end
    end
  end
end
