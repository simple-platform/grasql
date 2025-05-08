defmodule GraSQL.SchemaTest do
  use ExUnit.Case

  describe "resolve/2" do
    test "resolve/2 returns correctly structured resolution response" do
      # Create a simple resolution request
      resolution_request = {
        :query_id,
        "test_query_id",
        :strings,
        ["users", "id", "name", "email", "profile", "bio", "avatar"],
        :paths,
        [1, 0, 1, 4, 2, 0, 4],
        :path_dir,
        [0, 3],
        :path_types,
        [0, 1],
        :cols,
        [{0, [1, 2, 3]}, {4, [5, 6]}],
        # users (index 0) -> query (type 0)
        :ops,
        [{0, 0}]
      }

      # Call resolve
      result = GraSQL.Schema.resolve(resolution_request)

      # Basic validation of the response structure
      assert is_map(result)
      assert Map.has_key?(result, :query_id)
      assert Map.has_key?(result, :strings)
      assert Map.has_key?(result, :tables)
      assert Map.has_key?(result, :rels)
      assert Map.has_key?(result, :joins)
      assert Map.has_key?(result, :path_map)
      assert Map.has_key?(result, :cols)
      assert Map.has_key?(result, :ops)

      # Verify query_id is preserved
      assert result.query_id == "test_query_id"

      # Verify strings are present
      assert "users" in result.strings
      assert "id" in result.strings
      assert "public" in result.strings

      # Verify at least one table
      assert result.tables != []

      # Verify operations are preserved
      assert result.ops == [{0, 0}]

      # If we do have any relationships, verify their structure
      if result.rels != [] do
        rel = List.first(result.rels)

        # (src_table_idx, target_table_idx, type_code, join_table_idx, [src_col_idxs], [tgt_col_idxs])
        assert tuple_size(rel) == 6

        {_, _, _, _, src_cols, tgt_cols} = rel
        assert is_list(src_cols)
        assert is_list(tgt_cols)
      end
    end

    test "resolves multiple operations in a single query" do
      # Create a resolution request with multiple operations
      resolution_request = {
        :query_id,
        "multi_op_query_id",
        :strings,
        ["users", "id", "name", "posts", "title", "content"],
        :paths,
        [1, 0, 2, 0, 1, 3, 2, 0, 3],
        :path_dir,
        [0, 3, 6],
        :path_types,
        [0, 0, 1],
        :cols,
        [{0, [1, 2]}, {3, [4, 5]}],
        # users -> query, posts -> insert_mutation
        :ops,
        [{0, 0}, {3, 1}]
      }

      # Call resolve
      result = GraSQL.Schema.resolve(resolution_request)

      # Verify response structure
      assert is_map(result)
      assert Map.has_key?(result, :query_id)
      assert result.query_id == "multi_op_query_id"

      # Verify tables
      assert not Enum.empty?(result.tables)

      # Both users and posts should be in the resolved tables
      assert "users" in result.strings
      assert "posts" in result.strings

      # Verify operations
      assert length(result.ops) == 2
    end

    test "handles complex nested relationships" do
      # Create a resolution request with nested relationships
      resolution_request = {
        :query_id,
        "nested_query_id",
        :strings,
        ["users", "id", "posts", "title", "comments", "content"],
        :paths,
        [1, 0, 2, 0, 2, 2, 3, 3, 0, 2, 3, 4],
        :path_dir,
        [0, 2, 6],
        # users, users.posts, users.posts.comments
        :path_types,
        [0, 1, 1],
        :cols,
        [{0, [1]}, {2, [3]}, {4, [5]}],
        # users -> query
        :ops,
        [{0, 0}]
      }

      # Call resolve
      result = GraSQL.Schema.resolve(resolution_request)

      # Verify response structure
      assert is_map(result)
      assert Map.has_key?(result, :query_id)
      assert result.query_id == "nested_query_id"

      # Verify tables and path_map
      assert not Enum.empty?(result.tables)
      assert length(result.path_map) > 0

      # Verify table names are in the strings
      assert "users" in result.strings

      # If we have relationships, verify their structure
      if result.rels != [] do
        rel = List.first(result.rels)
        assert tuple_size(rel) == 6
      end
    end

    test "resolves columns with their attributes" do
      # Create a simple resolution request
      resolution_request = {
        :query_id,
        "columns_query_id",
        :strings,
        ["users", "id", "name", "email"],
        :paths,
        [2, 0, 1, 0],
        :path_dir,
        [0],
        # just users table
        :path_types,
        [0],
        :cols,
        [{0, [1, 2, 3]}],
        # users -> query
        :ops,
        [{0, 0}]
      }

      # Call resolve
      result = GraSQL.Schema.resolve(resolution_request)

      # Verify columns are resolved
      assert length(result.cols) > 0

      # Check for column types and attributes in strings
      assert "integer" in result.strings
      assert "text" in result.strings
    end

    test "handles empty input gracefully" do
      # Create an empty resolution request
      resolution_request = {
        :query_id,
        "empty_query_id",
        :strings,
        [],
        :paths,
        [],
        :path_dir,
        [],
        :path_types,
        [],
        :cols,
        [],
        :ops,
        []
      }

      # Call resolve - should not crash
      result = GraSQL.Schema.resolve(resolution_request)

      # Verify basic structure is maintained
      assert is_map(result)
      assert Map.has_key?(result, :query_id)
      assert result.query_id == "empty_query_id"
      assert Enum.empty?(result.tables)
      assert Enum.empty?(result.rels)
      assert Enum.empty?(result.path_map)
    end
  end
end
