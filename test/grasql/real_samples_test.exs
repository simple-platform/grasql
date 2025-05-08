defmodule GraSQL.RealSamplesTest do
  @moduledoc """
  Tests that validate ResolutionRequest and ResolutionResponse using the actual samples
  from the docs/samples directory.

  These tests extract the GraphQL queries, expected ResolutionRequest, and expected
  ResolutionResponse directly from the sample markdown files.
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
    resolver_fn = fn request ->
      # Extract the first operation's field name from request
      {field_idx, _} = hd(elem(request, 6))
      field_name = Enum.at(elem(request, 2), field_idx)

      # Return a mock SQL response
      {:sql, "SELECT * FROM #{field_name}"}
    end

    SchemaResolverCache.put_resolver("default", resolver_fn)

    :ok
  end

  @doc """
  Extract GraphQL query, expected ResolutionRequest, and expected ResolutionResponse
  from a sample markdown file.
  """
  def extract_sample_data(sample_number) do
    # Format sample number with leading zeros if needed
    sample_name = String.pad_leading(Integer.to_string(sample_number), 2, "0")
    sample_path = "docs/samples/#{sample_name}-"

    # Find matching sample file
    {:ok, files} = File.ls("docs/samples")

    sample_file =
      Enum.find(files, fn file ->
        String.starts_with?(file, sample_name <> "-")
      end)

    if sample_file == nil do
      raise "Sample file for #{sample_name} not found"
    end

    # Read file content
    sample_content = File.read!("docs/samples/#{sample_file}")

    # Extract GraphQL query
    graphql_regex = ~r/```graphql\s+([\s\S]*?)\s+```/
    [_, graphql_query] = Regex.run(graphql_regex, sample_content)

    # Extract expected ResolutionRequest
    request_regex =
      ~r/```json\s+(\{\s+"query_id".*?"ops":\s+\[\[.*?\]\]\s+\})\s+```\s+-\s+`query_id`/s

    [_, request_json] = Regex.run(request_regex, sample_content)

    # Extract expected ResolutionResponse
    response_regex =
      ~r/```json\s+(\{\s+"query_id".*?"ops":\s+\[\[.*?\]\]\s+\})\s+```\s+-\s+`tables`/s

    response_json =
      case Regex.run(response_regex, sample_content) do
        [_, json] -> json
        # Some samples might not have a ResolutionResponse
        nil -> nil
      end

    {graphql_query, request_json, response_json}
  end

  @doc """
  Parse JSON into a ResolutionRequest tuple
  """
  def parse_request_json(json) do
    req = Jason.decode!(json)

    query_id = req["query_id"]
    strings = req["strings"]
    paths = req["paths"]
    path_dir = req["path_dir"]
    path_types = req["path_types"]

    # Convert cols and ops from nested arrays to tuples
    cols = Enum.map(req["cols"], fn [idx, columns] -> {idx, columns} end)
    ops = Enum.map(req["ops"], fn [idx, op_type] -> {idx, op_type} end)

    {:resolution_request, query_id, strings, paths, path_dir, path_types, cols, ops}
  end

  @doc """
  Compare generated ResolutionRequest with expected ResolutionRequest
  """
  def compare_requests(actual, expected) do
    # Compare query_id - should be the same
    assert elem(actual, 1) == elem(expected, 1), "Query ID mismatch"

    # Compare strings - should contain all the expected strings
    actual_strings = elem(actual, 2)
    expected_strings = elem(expected, 2)

    Enum.each(expected_strings, fn str ->
      assert str in actual_strings, "String '#{str}' not found in actual request"
    end)

    # Compare operation types
    actual_ops = elem(actual, 6)
    expected_ops = elem(expected, 6)

    Enum.each(expected_ops, fn {idx, op_type} ->
      # Find the operation for the same field name
      field_name = Enum.at(expected_strings, idx)
      actual_field_idx = Enum.find_index(actual_strings, fn s -> s == field_name end)

      actual_op = Enum.find(actual_ops, fn {i, _} -> i == actual_field_idx end)
      assert actual_op != nil, "No operation found for field '#{field_name}'"

      {_, actual_op_type} = actual_op
      assert actual_op_type == op_type, "Operation type mismatch for field '#{field_name}'"
    end)
  end

  @doc """
  Run test for a specific sample
  """
  def test_sample(sample_number) do
    {graphql_query, request_json, _response_json} = extract_sample_data(sample_number)

    # Parse expected request from JSON
    expected_request = parse_request_json(request_json)

    # Parse GraphQL query to get actual request
    {:ok, {_info, actual_request}} = GraSQL.Native.parse_graphql(graphql_query)

    # Compare actual request with expected request
    compare_requests(actual_request, expected_request)

    # Resolve request to get response
    response = Schema.resolve("default", actual_request)

    # Verify response structure
    assert is_tuple(response)
    assert tuple_size(response) >= 8
    assert elem(response, 0) == :resolution_response

    # Verify query_id matches
    assert elem(response, 1) == elem(actual_request, 1)

    # Verify document caching
    cached_doc = GraSQL.Native.get_from_cache(elem(actual_request, 1))
    assert cached_doc != nil, "Document should be cached"
  end

  # Define tests for all samples
  for sample_number <- 1..20 do
    @sample_number sample_number
    test "Sample #{sample_number} generates correct ResolutionRequest" do
      test_sample(@sample_number)
    end
  end
end
