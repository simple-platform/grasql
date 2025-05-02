defmodule GraSQL.NativeTest do
  use ExUnit.Case, async: true

  alias GraSQL.Native

  describe "parse_query/1" do
    test "parses a simple query" do
      query = "query { users { id name email } }"
      assert {:ok, _query_id, :query, "", resolution_request} = Native.parse_query(query)
      assert is_tuple(resolution_request) or is_map(resolution_request)
    end

    test "parses a named query" do
      query = "query GetUsers { users { id name } }"
      assert {:ok, _query_id, :query, "GetUsers", resolution_request} = Native.parse_query(query)
      assert is_tuple(resolution_request) or is_map(resolution_request)
    end

    test "parses a mutation" do
      query = "mutation CreateUser { createUser(name: \"John\") { id } }"

      assert {:ok, _query_id, :mutation, "CreateUser", resolution_request} =
               Native.parse_query(query)

      assert is_tuple(resolution_request) or is_map(resolution_request)
    end

    test "caches parsed queries" do
      # Parse a query twice and ensure same query ID is returned
      query = "query { users { id } }"
      assert {:ok, query_id1, _, _, _} = Native.parse_query(query)
      assert {:ok, query_id2, _, _, _} = Native.parse_query(query)
      assert query_id1 == query_id2

      # Sleep to allow cache to expire (if TTL is configured)
      Process.sleep(1100)
      assert {:ok, query_id3, _, _, _} = Native.parse_query(query)

      # Same query ID should be returned after cache expiry
      assert query_id1 == query_id3
    end

    test "handles invalid queries" do
      invalid_query = "query { invalid syntax"
      assert {:error, _reason} = Native.parse_query(invalid_query)
    end

    test "handles cache eviction" do
      # Parse multiple different queries to test cache behavior
      queries = [
        "query { users { id } }",
        "query { posts { id } }",
        "query { comments { id } }",
        "query { profiles { id } }"
      ]

      Enum.each(queries, fn query ->
        assert {:ok, _, _, _, _} = Native.parse_query(query)
      end)

      # All queries should work, even with cache limits
      # We're not testing specific eviction strategies, just basic functionality
    end

    test "returns resolution_request with field_names and field_paths" do
      query = "query { users { id posts { title comments { body } } } }"
      assert {:ok, _query_id, :query, "", resolution_request} = Native.parse_query(query)

      # Extract field_names and field_paths based on the resolution_request format
      {field_names_key, field_names, field_paths_key, field_paths} = resolution_request

      # Verify atom keys
      assert field_names_key == :field_names
      assert field_paths_key == :field_paths

      # Verify field_names is a list of strings
      assert is_list(field_names)
      assert Enum.all?(field_names, &is_binary/1)

      # Verify field_paths is a list
      assert is_list(field_paths)
    end
  end

  describe "generate_sql/2" do
    setup do
      # Pre-parse query to get ID
      query = "query { users { id name } }"
      {:ok, query_id, _, _, _} = Native.parse_query(query)

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
