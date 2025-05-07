defmodule GraSQL.SchemaResolverCacheTest do
  use ExUnit.Case

  describe "get_resolver/0" do
    test "returns the cached resolver" do
      # We already inserted the test resolver in test_helper.exs
      assert {:ok, resolver} = GraSQL.SchemaResolverCache.get_resolver()
      assert resolver == GraSQL.TestResolver
    end

    test "returns error when resolver not found" do
      # Temporarily clear the cache
      :ets.delete(:grasql_resolver_cache, :schema_resolver)

      # Should return error
      assert {:error, _} = GraSQL.SchemaResolverCache.get_resolver()

      # Put it back for other tests
      :ets.insert(:grasql_resolver_cache, {:schema_resolver, GraSQL.TestResolver})
    end
  end

  test "GenServer initialization can be called" do
    # Just check the initialization function itself without starting the GenServer
    # since it's already started in the test_helper
    state = GraSQL.SchemaResolverCache.init([])
    assert {:ok, %{table: :grasql_resolver_cache}} = state
  end
end
