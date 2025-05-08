defmodule GraSQL.IntegrationTest do
  @moduledoc """
  Integration tests that validate the full pipeline from GraphQL parsing to ResolutionResponse
  generation for all sample patterns.

  These tests verify that Phase 1 (parsing) and Phase 2 (resolution) work together correctly
  for all the sample GraphQL query patterns.
  """

  use ExUnit.Case

  alias GraSQL.Schema
  alias GraSQL.SchemaResolverCache

  setup do
    # Initialize GraSQL for testing
    GraSQL.Native.initialize_for_test()

    # Ensure schema resolver cache is started
    {:ok, _} = SchemaResolverCache.start_link([])

    # Setup test resolver function
    resolver_fn = fn _req -> {:sql, "SELECT * FROM test"} end
    SchemaResolverCache.put_resolver("default", resolver_fn)

    :ok
  end

  @doc """
  Helper function to process a GraphQL query through parsing and resolution
  """
  def process_query(query) do
    # Phase 1: Parse query to ResolutionRequest
    {:ok, {info, request}} = GraSQL.Native.parse_graphql(query)

    # Phase 2: Resolve request to ResolutionResponse
    response = Schema.resolve("default", request)

    {info, request, response}
  end

  @doc """
  Helper function to verify document caching
  """
  def verify_document_caching(query) do
    # Parse once to cache
    {:ok, {info, _}} = GraSQL.Native.parse_graphql(query)
    query_id = info.query_id

    # Parse again - should hit cache
    {:ok, {cached_info, _}} = GraSQL.Native.parse_graphql(query)

    # Verify same query_id
    assert cached_info.query_id == query_id

    # Check cache for the document
    cached_doc = GraSQL.Native.get_from_cache(query_id)
    assert cached_doc != nil, "Document should be in cache"

    # Verify we can use the document
    assert cached_info.document_ptr != nil, "Document pointer should not be nil"
    assert cached_info.document() != nil, "Should be able to get document from pointer"
  end

  @doc """
  Helper function to verify response structure
  """
  def verify_response_structure(response, expected_op_type) do
    # Basic structure checks
    assert is_tuple(response)
    assert tuple_size(response) >= 8
    assert elem(response, 0) == :resolution_response

    # Verify query_id
    assert elem(response, 1) != nil

    # Verify fields
    fields = elem(response, 2)
    assert is_list(fields)
    assert length(fields) > 0

    # Verify operation type
    ops = elem(response, 7)
    assert length(ops) > 0

    # Get first operation
    {_, op_type} = Enum.at(ops, 0)

    assert op_type == expected_op_type,
           "Expected operation type #{expected_op_type}, got #{op_type}"
  end

  #
  # Basic Query Tests (Samples 1-2)
  #
  test "Sample 1: Simple Query integrates parsing and resolution correctly" do
    query = """
    {
      users {
        id
        name
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :query

    # Verify response structure
    # 0 = query
    verify_response_structure(response, 0)

    # Verify caching
    verify_document_caching(query)
  end

  test "Sample 2: Query with Arguments integrates parsing and resolution correctly" do
    query = """
    {
      user(id: 123) {
        id
        name
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :query

    # Verify response structure
    # 0 = query
    verify_response_structure(response, 0)

    # Verify caching
    verify_document_caching(query)
  end

  #
  # Relationship Tests (Samples 3, 13)
  #
  test "Sample 3: Basic Relationship integrates parsing and resolution correctly" do
    query = """
    {
      users {
        id
        posts {
          title
        }
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :query

    # Verify response structure
    # 0 = query
    verify_response_structure(response, 0)

    # Verify fields
    fields = elem(response, 2)
    assert "users" in fields
    assert "posts" in fields

    # Verify caching
    verify_document_caching(query)
  end

  test "Sample 13: Many-to-Many Relationship integrates parsing and resolution correctly" do
    query = """
    {
      users {
        id
        name
        categories {
          name
        }
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :query

    # Verify response structure
    # 0 = query
    verify_response_structure(response, 0)

    # Verify fields
    fields = elem(response, 2)
    assert "users" in fields
    assert "categories" in fields

    # Verify caching
    verify_document_caching(query)
  end

  #
  # Filtering Tests (Samples 4, 5, 12)
  #
  test "Sample 4: Basic Filtering integrates parsing and resolution correctly" do
    query = """
    {
      users(where: { name: { _eq: "John" } }) {
        id
        name
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :query

    # Verify response structure
    # 0 = query
    verify_response_structure(response, 0)

    # Verify caching
    verify_document_caching(query)
  end

  test "Sample 5: Nested Filtering integrates parsing and resolution correctly" do
    query = """
    {
      users(where: { posts: { title: { _like: "%test%" } } }) {
        id
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :query

    # Verify response structure
    # 0 = query
    verify_response_structure(response, 0)

    # Verify caching
    verify_document_caching(query)
  end

  test "Sample 12: Complex Boolean Logic integrates parsing and resolution correctly" do
    query = """
    {
      users(
        where: {
          _or: [
            { name: { _like: "%John%" } }
            { _and: [{ age: { _gt: 30 } }, { active: { _eq: true } }] }
          ]
        }
      ) {
        id
        name
        age
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :query

    # Verify response structure
    # 0 = query
    verify_response_structure(response, 0)

    # Verify caching
    verify_document_caching(query)
  end

  #
  # Pagination and Sorting Tests (Samples 6, 7)
  #
  test "Sample 6: Pagination integrates parsing and resolution correctly" do
    query = """
    {
      users(limit: 10, offset: 20) {
        id
        name
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :query

    # Verify response structure
    # 0 = query
    verify_response_structure(response, 0)

    # Verify caching
    verify_document_caching(query)
  end

  test "Sample 7: Sorting integrates parsing and resolution correctly" do
    query = """
    {
      users(order_by: { name: asc }) {
        id
        name
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :query

    # Verify response structure
    # 0 = query
    verify_response_structure(response, 0)

    # Verify caching
    verify_document_caching(query)
  end

  #
  # Aggregation Tests (Samples 8, 9, 10)
  #
  test "Sample 8: Basic Aggregation integrates parsing and resolution correctly" do
    query = """
    {
      users_aggregate {
        aggregate {
          count
        }
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :query

    # Verify response structure
    # 0 = query
    verify_response_structure(response, 0)

    # Verify caching
    verify_document_caching(query)
  end

  test "Sample 9: Aggregation with Nodes integrates parsing and resolution correctly" do
    query = """
    {
      users_aggregate {
        aggregate {
          count
          max {
            id
          }
        }
        nodes {
          name
        }
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :query

    # Verify response structure
    # 0 = query
    verify_response_structure(response, 0)

    # Verify caching
    verify_document_caching(query)
  end

  test "Sample 10: Nested Aggregation integrates parsing and resolution correctly" do
    query = """
    {
      users {
        id
        name
        posts_aggregate {
          aggregate {
            count
          }
        }
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :query

    # Verify response structure
    # 0 = query
    verify_response_structure(response, 0)

    # Verify caching
    verify_document_caching(query)
  end

  #
  # Distinct Queries Test (Sample 11)
  #
  test "Sample 11: Distinct Queries integrates parsing and resolution correctly" do
    query = """
    {
      users(distinct_on: name) {
        id
        name
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :query

    # Verify response structure
    # 0 = query
    verify_response_structure(response, 0)

    # Verify caching
    verify_document_caching(query)
  end

  #
  # Complex Combined Query Test (Sample 14)
  #
  test "Sample 14: Complex Combined Query integrates parsing and resolution correctly" do
    query = """
    {
      users(
        where: { age: { _gt: 21 } }
        order_by: { name: asc }
        limit: 5
        offset: 10
      ) {
        id
        name
        posts(
          where: { published: { _eq: true } }
          order_by: { created_at: desc }
          limit: 3
        ) {
          title
          content
        }
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :query

    # Verify response structure
    # 0 = query
    verify_response_structure(response, 0)

    # Verify fields
    fields = elem(response, 2)
    assert "users" in fields
    assert "posts" in fields

    # Verify caching
    verify_document_caching(query)
  end

  #
  # Mutation Tests (Samples 15-20)
  #
  test "Sample 15: Insert Mutation integrates parsing and resolution correctly" do
    query = """
    mutation {
      insert_users_one(
        object: { name: "John Doe", email: "john@example.com", age: 30 }
      ) {
        id
        name
        email
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :insert_mutation

    # Verify response structure
    # 1 = insert
    verify_response_structure(response, 1)

    # Verify caching
    verify_document_caching(query)
  end

  test "Sample 16: Batch Insert Mutation integrates parsing and resolution correctly" do
    query = """
    mutation {
      insert_users(
        objects: [
          { name: "John Doe", email: "john@example.com", age: 30 }
          { name: "Jane Smith", email: "jane@example.com", age: 28 }
        ]
      ) {
        affected_rows
        returning {
          id
          name
        }
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :insert_mutation

    # Verify response structure
    # 1 = insert
    verify_response_structure(response, 1)

    # Verify caching
    verify_document_caching(query)
  end

  test "Sample 17: Update Mutation integrates parsing and resolution correctly" do
    query = """
    mutation {
      update_users_by_pk(
        pk_columns: { id: 123 }
        _set: { name: "Updated Name", email: "updated@example.com" }
      ) {
        id
        name
        email
        updated_at
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :update_mutation

    # Verify response structure
    # 2 = update
    verify_response_structure(response, 2)

    # Verify caching
    verify_document_caching(query)
  end

  test "Sample 18: Batch Update Mutation integrates parsing and resolution correctly" do
    query = """
    mutation {
      update_users(
        where: { active: { _eq: false } }
        _set: { active: true, updated_at: "2023-06-15T12:00:00Z" }
      ) {
        affected_rows
        returning {
          id
          name
          active
          updated_at
        }
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :update_mutation

    # Verify response structure
    # 2 = update
    verify_response_structure(response, 2)

    # Verify caching
    verify_document_caching(query)
  end

  test "Sample 19: Delete Mutation integrates parsing and resolution correctly" do
    query = """
    mutation {
      delete_users_by_pk(id: 123) {
        id
        name
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :delete_mutation

    # Verify response structure
    # 3 = delete
    verify_response_structure(response, 3)

    # Verify caching
    verify_document_caching(query)
  end

  test "Sample 20: Batch Delete Mutation integrates parsing and resolution correctly" do
    query = """
    mutation {
      delete_users(
        where: {
          last_login: { _lt: "2022-01-01T00:00:00Z" }
          active: { _eq: false }
        }
      ) {
        affected_rows
        returning {
          id
          name
          email
        }
      }
    }
    """

    {info, request, response} = process_query(query)

    # Verify operation kind
    assert info.operation_kind == :delete_mutation

    # Verify response structure
    # 3 = delete
    verify_response_structure(response, 3)

    # Verify caching
    verify_document_caching(query)
  end
end
