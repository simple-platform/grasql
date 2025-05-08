defmodule GraSQL.SamplesTest do
  @moduledoc """
  Tests that validate ResolutionResponse generation for all sample GraphQL queries.
  These tests verify that the schema resolution phase (Phase 2) correctly
  processes ResolutionRequests and generates the expected ResolutionResponse.
  """

  use ExUnit.Case

  alias GraSQL.Schema
  alias GraSQL.SchemaResolverCache

  setup do
    # Ensure schema resolver cache is started
    {:ok, _} = SchemaResolverCache.start_link([])
    :ok
  end

  @doc """
  Helper function to verify basic ResolutionResponse structure
  """
  def verify_basic_structure(response, field, path_type, expected_path_count) do
    # Verify basic structure
    assert is_tuple(response)
    assert tuple_size(response) >= 5
    assert elem(response, 0) == :resolution_response
    assert elem(response, 1) != nil, "ResolutionResponse should have a query_id"

    # Verify fields
    fields = elem(response, 2)
    assert is_list(fields)
    assert Enum.member?(fields, field), "Field '#{field}' not found in ResolutionResponse fields"

    # Verify paths
    paths = elem(response, 3)
    assert is_list(paths)
    assert length(paths) >= expected_path_count, "Expected at least #{expected_path_count} paths"

    # Verify path types
    path_types = elem(response, 4)
    assert is_list(path_types)

    assert length(path_types) >= expected_path_count,
           "Expected at least #{expected_path_count} path types"

    # Verify there is at least one path with the expected type
    assert Enum.any?(path_types, fn type -> type == path_type end),
           "No path with type #{path_type} found in ResolutionResponse"
  end

  @doc """
  Helper function to verify that a path with given field exists and has expected columns
  """
  def verify_path_columns(response, field, expected_columns) do
    # Get fields
    fields = elem(response, 2)
    field_idx = Enum.find_index(fields, fn f -> f == field end)
    assert field_idx != nil, "Field '#{field}' not found in ResolutionResponse fields"

    # Verify columns are present for the field
    columns = elem(response, 5)
    field_columns = Enum.find(columns, fn {idx, _cols} -> idx == field_idx end)

    assert field_columns != nil, "No columns found for field '#{field}'"

    {_, cols} = field_columns

    Enum.each(expected_columns, fn column ->
      col_idx = Enum.find_index(fields, fn f -> f == column end)
      assert col_idx != nil, "Column '#{column}' not found in ResolutionResponse fields"
      assert col_idx in cols, "Column '#{column}' not found for field '#{field}'"
    end)
  end

  @doc """
  Helper function to verify a relationship exists between parent and child fields
  """
  def verify_relationship(response, parent_field, child_field) do
    # Get fields
    fields = elem(response, 2)
    parent_idx = Enum.find_index(fields, fn f -> f == parent_field end)
    child_idx = Enum.find_index(fields, fn f -> f == child_field end)

    assert parent_idx != nil,
           "Parent field '#{parent_field}' not found in ResolutionResponse fields"

    assert child_idx != nil, "Child field '#{child_field}' not found in ResolutionResponse fields"

    # Find a relationship path that connects parent and child
    paths = elem(response, 3)
    path_types = elem(response, 4)
    path_dirs = elem(response, 6)

    relationship_found = find_relationship(paths, path_types, path_dirs, parent_idx, child_idx)

    assert relationship_found,
           "No relationship path found between #{parent_field} and #{child_field}"
  end

  defp find_relationship(paths, path_types, path_dirs, parent_idx, child_idx) do
    Enum.with_index(path_types)
    |> Enum.any?(fn {type, path_idx} ->
      # Only consider relationship type paths
      type == 1 and path_connects_nodes?(paths, path_dirs, path_idx, parent_idx, child_idx)
    end)
  end

  defp path_connects_nodes?(paths, path_dirs, path_idx, parent_idx, child_idx) do
    start_offset = Enum.at(path_dirs, path_idx)

    end_offset =
      if path_idx + 1 < length(path_dirs) do
        Enum.at(path_dirs, path_idx + 1)
      else
        length(paths)
      end

    path_length = Enum.at(paths, start_offset)
    path = Enum.slice(paths, (start_offset + 1)..(start_offset + path_length))

    # Check if path connects parent and child
    parent_idx in path and child_idx in path
  end

  @doc """
  Helper function to verify operation type for a field
  """
  def verify_operation_type(response, field, expected_op_type) do
    # Get fields
    fields = elem(response, 2)
    field_idx = Enum.find_index(fields, fn f -> f == field end)
    assert field_idx != nil, "Field '#{field}' not found in ResolutionResponse fields"

    # Verify operation type
    ops = elem(response, 7)
    field_op = Enum.find(ops, fn {idx, _op} -> idx == field_idx end)

    assert field_op != nil, "No operation found for field '#{field}'"
    {_, op_type} = field_op

    assert op_type == expected_op_type,
           "Expected operation type #{expected_op_type} for field '#{field}', got #{op_type}"
  end

  @doc """
  Helper function to generate a ResolutionRequest for testing
  """
  def create_resolution_request(query_id, strings, paths, path_dir, path_types, cols, ops) do
    {:resolution_request, query_id, strings, paths, path_dir, path_types, cols, ops}
  end

  @doc """
  Helper function to resolve a request and verify basic structure
  """
  def resolve_and_verify(
        request,
        root_field,
        expected_op_type,
        expected_path_count \\ 1
      ) do
    # Call schema resolver
    resolver_fn = fn _req -> {:sql, "SELECT * FROM #{root_field}"} end
    SchemaResolverCache.put_resolver("default", resolver_fn)

    response = Schema.resolve("default", request)

    # Verify basic structure
    verify_basic_structure(response, root_field, 0, expected_path_count)

    # Verify operation type
    verify_operation_type(response, root_field, expected_op_type)

    response
  end

  #
  # Tests for basic queries (Sample 1 and 2)
  #
  test "Sample 1: Simple Query generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "9f8b20e3d7c64e7a",
        ["users", "id", "name"],
        [1, 0],
        [0],
        [0],
        [{0, [1, 2]}],
        [{0, 0}]
      )

    response = resolve_and_verify(request, "users", 0)

    # Verify columns
    verify_path_columns(response, "users", ["id", "name"])
  end

  test "Sample 2: Query with Arguments generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "8d7f61a5c2b34c9e",
        ["user", "id", "name"],
        [1, 0],
        [0],
        [0],
        [{0, [1, 2]}],
        [{0, 0}]
      )

    response = resolve_and_verify(request, "user", 0)

    # Verify columns
    verify_path_columns(response, "user", ["id", "name"])
  end

  #
  # Tests for relationships (Sample 3 and 13)
  #
  test "Sample 3: Basic Relationship generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "7c6b52a4d9e83f10",
        ["users", "id", "posts", "title"],
        [1, 0, 2, 1, 3],
        [0, 3],
        [0, 1],
        [{0, [1]}, {2, [3]}],
        [{0, 0}]
      )

    response = resolve_and_verify(request, "users", 0, 2)

    # Verify columns
    verify_path_columns(response, "users", ["id"])
    verify_path_columns(response, "posts", ["title"])

    # Verify relationship
    verify_relationship(response, "users", "posts")
  end

  test "Sample 13: Many-to-Many Relationship generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "5a4b3c2d1e0f9g8h",
        ["users", "id", "name", "categories", "name"],
        [1, 0, 3, 1, 2, 4],
        [0, 3],
        [0, 1],
        [{0, [1, 2]}, {3, [4]}],
        [{0, 0}]
      )

    response = resolve_and_verify(request, "users", 0, 2)

    # Verify columns
    verify_path_columns(response, "users", ["id", "name"])
    verify_path_columns(response, "categories", ["name"])

    # Verify relationship
    verify_relationship(response, "users", "categories")
  end

  #
  # Tests for filtering (Samples 4, 5, 12)
  #
  test "Sample 4: Basic Filtering generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "6f5e4d3c2b1a0987",
        ["users", "id", "name"],
        [1, 0],
        [0],
        [0],
        [{0, [1, 2]}],
        [{0, 0}]
      )

    response = resolve_and_verify(request, "users", 0)

    # Verify columns
    verify_path_columns(response, "users", ["id", "name"])
  end

  test "Sample 5: Nested Filtering generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "5e4d3c2b1a098765",
        ["users", "id", "posts", "title"],
        [1, 0, 2, 1, 3],
        [0, 3],
        [0, 1],
        [{0, [1]}, {2, [3]}],
        [{0, 0}]
      )

    response = resolve_and_verify(request, "users", 0, 2)

    # Verify columns
    verify_path_columns(response, "users", ["id"])
    verify_path_columns(response, "posts", ["title"])

    # Verify relationship
    verify_relationship(response, "users", "posts")
  end

  test "Sample 12: Complex Boolean Logic generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "4d3c2b1a09876543",
        ["users", "id", "name", "age", "active"],
        [1, 0],
        [0],
        [0],
        [{0, [1, 2, 3]}],
        [{0, 0}]
      )

    response = resolve_and_verify(request, "users", 0)

    # Verify columns
    verify_path_columns(response, "users", ["id", "name", "age"])
  end

  #
  # Tests for pagination and sorting (Samples 6, 7)
  #
  test "Sample 6: Pagination generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "3c2b1a0987654321",
        ["users", "id", "name"],
        [1, 0],
        [0],
        [0],
        [{0, [1, 2]}],
        [{0, 0}]
      )

    response = resolve_and_verify(request, "users", 0)

    # Verify columns
    verify_path_columns(response, "users", ["id", "name"])
  end

  test "Sample 7: Sorting generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "2b1a098765432109",
        ["users", "id", "name"],
        [1, 0],
        [0],
        [0],
        [{0, [1, 2]}],
        [{0, 0}]
      )

    response = resolve_and_verify(request, "users", 0)

    # Verify columns
    verify_path_columns(response, "users", ["id", "name"])
  end

  #
  # Tests for aggregation (Samples 8, 9, 10)
  #
  test "Sample 8: Basic Aggregation generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "1a0987654321fedcba",
        ["users_aggregate", "aggregate", "count"],
        [1, 0],
        [0],
        [0],
        [{0, [2]}],
        [{0, 0}]
      )

    response = resolve_and_verify(request, "users_aggregate", 0)

    # Verify columns
    verify_path_columns(response, "users_aggregate", ["count"])
  end

  test "Sample 9: Aggregation with Nodes generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "a0987654321fedcba9",
        ["users_aggregate", "aggregate", "count", "max", "id", "nodes", "name"],
        [1, 0],
        [0],
        [0],
        [{0, [2, 4, 6]}],
        [{0, 0}]
      )

    response = resolve_and_verify(request, "users_aggregate", 0)

    # Verify columns
    verify_path_columns(response, "users_aggregate", ["count", "id", "name"])
  end

  test "Sample 10: Nested Aggregation generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "987654321fedcba987",
        ["users", "id", "name", "posts_aggregate", "aggregate", "count"],
        [1, 0, 3, 1, 2, 5],
        [0, 3],
        [0, 1],
        [{0, [1, 2]}, {3, [5]}],
        [{0, 0}]
      )

    response = resolve_and_verify(request, "users", 0, 2)

    # Verify columns
    verify_path_columns(response, "users", ["id", "name"])
    verify_path_columns(response, "posts_aggregate", ["count"])

    # Verify relationship
    verify_relationship(response, "users", "posts_aggregate")
  end

  #
  # Test for distinct queries (Sample 11)
  #
  test "Sample 11: Distinct Queries generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "76543210fedcba9876",
        ["users", "id", "name"],
        [1, 0],
        [0],
        [0],
        [{0, [1, 2]}],
        [{0, 0}]
      )

    response = resolve_and_verify(request, "users", 0)

    # Verify columns
    verify_path_columns(response, "users", ["id", "name"])
  end

  #
  # Test for complex combined query (Sample 14)
  #
  test "Sample 14: Complex Combined Query generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "6543210fedcba98765",
        ["users", "id", "name", "posts", "title", "content", "age", "published", "created_at"],
        [1, 0, 3, 1, 2, 4, 5],
        [0, 3],
        [0, 1],
        [{0, [1, 2, 6]}, {3, [4, 5, 7, 8]}],
        [{0, 0}]
      )

    response = resolve_and_verify(request, "users", 0, 2)

    # Verify columns
    verify_path_columns(response, "users", ["id", "name", "age"])
    verify_path_columns(response, "posts", ["title", "content"])

    # Verify relationship
    verify_relationship(response, "users", "posts")
  end

  #
  # Tests for insert mutations (Samples 15, 16)
  #
  test "Sample 15: Insert Mutation generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "543210fedcba987654",
        ["insert_users_one", "id", "name", "email", "age"],
        [1, 0],
        [0],
        [0],
        [{0, [1, 2, 3]}],
        # 1 = insert operation
        [{0, 1}]
      )

    response = resolve_and_verify(request, "insert_users_one", 1)

    # Verify columns
    verify_path_columns(response, "insert_users_one", ["id", "name", "email"])
  end

  test "Sample 16: Batch Insert Mutation generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "43210fedcba9876543",
        ["insert_users", "affected_rows", "returning", "id", "name", "email", "age"],
        [1, 0],
        [0],
        [0],
        [{0, [1, 3, 4]}],
        # 1 = insert operation
        [{0, 1}]
      )

    response = resolve_and_verify(request, "insert_users", 1)

    # Verify columns
    verify_path_columns(response, "insert_users", ["affected_rows", "id", "name"])
  end

  #
  # Tests for update mutations (Samples 17, 18)
  #
  test "Sample 17: Update Mutation generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "3210fedcba98765432",
        ["update_users_by_pk", "id", "name", "email", "updated_at"],
        [1, 0],
        [0],
        [0],
        [{0, [1, 2, 3, 4]}],
        # 2 = update operation
        [{0, 2}]
      )

    response = resolve_and_verify(request, "update_users_by_pk", 2)

    # Verify columns
    verify_path_columns(response, "update_users_by_pk", ["id", "name", "email", "updated_at"])
  end

  test "Sample 18: Batch Update Mutation generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "210fedcba9876543210",
        ["update_users", "affected_rows", "returning", "id", "name", "active", "updated_at"],
        [1, 0],
        [0],
        [0],
        [{0, [1, 3, 4, 5, 6]}],
        # 2 = update operation
        [{0, 2}]
      )

    response = resolve_and_verify(request, "update_users", 2)

    # Verify columns
    verify_path_columns(response, "update_users", [
      "affected_rows",
      "id",
      "name",
      "active",
      "updated_at"
    ])
  end

  #
  # Tests for delete mutations (Samples 19, 20)
  #
  test "Sample 19: Delete Mutation generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "10fedcba987654321f",
        ["delete_users_by_pk", "id", "name"],
        [1, 0],
        [0],
        [0],
        [{0, [1, 2]}],
        # 3 = delete operation
        [{0, 3}]
      )

    response = resolve_and_verify(request, "delete_users_by_pk", 3)

    # Verify columns
    verify_path_columns(response, "delete_users_by_pk", ["id", "name"])
  end

  test "Sample 20: Batch Delete Mutation generates correct ResolutionResponse" do
    request =
      create_resolution_request(
        "0fedcba987654321fe",
        [
          "delete_users",
          "affected_rows",
          "returning",
          "id",
          "name",
          "email",
          "last_login",
          "active"
        ],
        [1, 0],
        [0],
        [0],
        [{0, [1, 3, 4, 5]}],
        # 3 = delete operation
        [{0, 3}]
      )

    response = resolve_and_verify(request, "delete_users", 3)

    # Verify columns
    verify_path_columns(response, "delete_users", ["affected_rows", "id", "name", "email"])
  end
end
