defmodule GraSQL.SchemaResolverCacheTest do
  use ExUnit.Case

  describe "get_resolver/0" do
    test "returns the cached resolver" do
      # We already inserted the test resolver in test_helper.exs
      assert {:ok, resolver} = GraSQL.SchemaResolverCache.get_resolver()
      assert resolver == GraSQL.TestResolver
    end

  setup do
    # Store original state
    original_resolver = case :ets.lookup(:grasql_resolver_cache, :schema_resolver) do
      [{:schema_resolver, resolver}] -> resolver
      [] -> nil
    end

    # Ensure cleanup happens even if the test fails
    on_exit(fn ->
      if original_resolver do
        :ets.insert(:grasql_resolver_cache, {:schema_resolver, original_resolver})
      end
    end)

    %{original_resolver: original_resolver}
  end

  test "returns error when resolver not found" do
    # Temporarily clear the cache
    :ets.delete(:grasql_resolver_cache, :schema_resolver)

    # Should return error
    assert {:error, _} = GraSQL.SchemaResolverCache.get_resolver()
  end
  end

  test "GenServer initialization can be called" do
    # Just check the initialization function itself without starting the GenServer
    # since it's already started in the test_helper
    state = GraSQL.SchemaResolverCache.init([])
    assert {:ok, %{table: :grasql_resolver_cache}} = state
  end
end
