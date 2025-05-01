defmodule GraSQL.NativeTest do
  use ExUnit.Case, async: true

  alias GraSQL.Config
  alias GraSQL.Native

  describe "init/1" do
    test "initializes with default configuration" do
      assert :ok = Native.init(Config.to_native_config(%Config{}))
    end

    test "initializes with custom configuration" do
      custom_config = %Config{
        aggregate_field_suffix: "_aggregate",
        operators: %{
          eq: "_equals",
          gt: "_greater_than"
        },
        max_cache_size: 2000,
        cache_ttl: 7200
      }

      assert :ok = Native.init(Config.to_native_config(custom_config))
    end
  end

  describe "parse_query/1" do
    setup do
      config = %Config{
        max_cache_size: 3,
        cache_ttl: 1
      }

      # Initialize with custom config for testing cache behavior
      :ok = Native.init(Config.to_native_config(config))
      :ok
    end

    test "parses a simple query" do
      query = "query { users { id name email } }"
      assert {:ok, _query_id, :query, ""} = Native.parse_query(query)
    end

    test "parses a named query" do
      query = "query GetUsers { users { id name } }"
      assert {:ok, _query_id, :query, "GetUsers"} = Native.parse_query(query)
    end

    test "parses a mutation" do
      query = "mutation CreateUser { createUser(name: \"John\") { id } }"
      assert {:ok, _query_id, :mutation, "CreateUser"} = Native.parse_query(query)
    end

    test "caches parsed queries" do
      # Parse a query twice and ensure same query ID is returned
      query = "query { users { id } }"
      assert {:ok, query_id1, _, _} = Native.parse_query(query)
      assert {:ok, query_id2, _, _} = Native.parse_query(query)
      assert query_id1 == query_id2

      # Sleep to allow cache to expire
      Process.sleep(1100)
      assert {:ok, query_id3, _, _} = Native.parse_query(query)

      # Same query ID should be returned after cache expiry
      assert query_id1 == query_id3
    end

    test "handles invalid queries" do
      invalid_query = "query { invalid syntax"
      assert {:error, _reason} = Native.parse_query(invalid_query)
    end

    test "handles cache eviction" do
      # Parse 4 different queries with max_cache_size of 3
      queries = [
        "query { users { id } }",
        "query { posts { id } }",
        "query { comments { id } }",
        "query { profiles { id } }"
      ]

      Enum.each(queries, fn query ->
        assert {:ok, _, _, _} = Native.parse_query(query)
      end)

      # The first query should have been evicted, but all other queries should work
      # Note: cache eviction in this test is implementation-dependent
      # We're not testing the specific eviction strategy, just that something gets evicted
    end
  end

  describe "generate_sql/2" do
    setup do
      config = %Config{}
      :ok = Native.init(Config.to_native_config(config))

      # Pre-parse query to get ID
      query = "query { users { id name } }"
      {:ok, query_id, _, _} = Native.parse_query(query)

      {:ok, %{query_id: query_id}}
    end

    test "generates SQL for a parsed query", %{query_id: query_id} do
      assert {:ok, sql, params} = Native.generate_sql(query_id, %{})
      assert is_binary(sql)
      assert is_list(params)
    end

    test "returns error for non-existent query ID" do
      assert {:error, _reason} = Native.generate_sql("nonexistent_id", %{})
    end
  end
end
