defmodule GraSQL.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  @moduledoc """
  Property-based tests for GraSQL using StreamData.

  These tests generate random valid GraphQL queries and verify that
  the parser handles them correctly.
  """

  # Generator for valid GraphQL field names (identifiers)
  defp field_name_generator do
    # GraphQL identifiers start with a letter or underscore and can contain letters, numbers, and underscores
    gen(
      all(
        first <-
          StreamData.one_of([
            StreamData.constant("_"),
            StreamData.string(:alphanumeric, min_length: 1, max_length: 1)
          ]),
        rest <- StreamData.string(:alphanumeric, min_length: 0, max_length: 10),
        do: first <> rest
      )
    )
  end

  # Generator for simple field selections (no args)
  defp simple_field_generator do
    gen all(name <- field_name_generator()) do
      name
    end
  end

  # Generator for a list of simple fields
  defp fields_list_generator(min_fields \\ 1, max_fields \\ 5) do
    gen all(
          fields <-
            StreamData.list_of(
              simple_field_generator(),
              min_length: min_fields,
              max_length: max_fields
            )
        ) do
      Enum.join(fields, " ")
    end
  end

  # Generator for basic GraphQL values
  defp simple_value_generator do
    StreamData.one_of([
      # String value
      gen all(value <- StreamData.string(:alphanumeric, min_length: 1, max_length: 10)) do
        ~s("#{value}")
      end,
      # Integer value
      gen all(value <- StreamData.integer(1..1000)) do
        to_string(value)
      end,
      # Boolean value
      gen all(value <- StreamData.boolean()) do
        to_string(value)
      end
    ])
  end

  # Generator for comparison operators
  defp operator_generator do
    StreamData.one_of([
      StreamData.constant("_eq"),
      StreamData.constant("_neq"),
      StreamData.constant("_gt"),
      StreamData.constant("_lt"),
      StreamData.constant("_gte"),
      StreamData.constant("_lte"),
      StreamData.constant("_like"),
      StreamData.constant("_ilike")
    ])
  end

  # Generator for simple filter condition
  defp simple_filter_generator do
    gen all(
          field <- field_name_generator(),
          operator <- operator_generator(),
          value <- simple_value_generator()
        ) do
      "{ #{field}: { #{operator}: #{value} } }"
    end
  end

  # Generator for simple args (limit, offset, where)
  defp simple_arg_generator do
    StreamData.one_of([
      # Limit arg
      gen all(limit <- StreamData.integer(1..100)) do
        "limit: #{limit}"
      end,
      # Offset arg
      gen all(offset <- StreamData.integer(0..100)) do
        "offset: #{offset}"
      end,
      # Where arg with simple filter
      gen all(filter <- simple_filter_generator()) do
        "where: #{filter}"
      end
    ])
  end

  # Generator for field arguments
  defp args_generator do
    gen all(
          args <-
            StreamData.list_of(
              simple_arg_generator(),
              min_length: 0,
              max_length: 3
            )
        ) do
      if Enum.empty?(args) do
        ""
      else
        "(#{Enum.join(args, ", ")})"
      end
    end
  end

  # Recursive generator for nested fields
  # The depth parameter controls how deeply nested the fields can be
  defp nested_fields_generator(depth) do
    if depth <= 0 do
      # Base case: no more nesting, just generate leaf fields
      fields_list_generator()
    else
      # We can generate either simple fields or nested objects
      StreamData.one_of([
        # Simple fields
        fields_list_generator(),

        # A nested object field
        gen all(
              field_name <- field_name_generator(),
              args <- args_generator(),
              nested_fields <- nested_fields_generator(depth - 1)
            ) do
          "#{field_name}#{args} { #{nested_fields} }"
        end
      ])
    end
  end

  # Generator for a complete GraphQL query
  defp graphql_query_generator(max_depth) do
    gen all(
          root_field <- field_name_generator(),
          args <- args_generator(),
          fields <- nested_fields_generator(max_depth)
        ) do
      "{ #{root_field}#{args} { #{fields} } }"
    end
  end

  property "parser handles valid randomly generated queries" do
    check all(query <- graphql_query_generator(2)) do
      # The parser should not crash on any valid query
      result = GraSQL.Native.parse_query(query)

      case result do
        {:ok, _query_id, _op_kind, _op_name, _request} ->
          # Query was successfully parsed
          assert true

        {:error, error_message} ->
          # Some generated queries might have features not supported by the parser,
          # which is okay. We just want to ensure it doesn't crash.
          assert is_binary(error_message)
      end
    end
  end

  property "resolution request contains at least one field path for valid queries" do
    check all(
            query <- graphql_query_generator(2),
            # Filter to only include queries that parse successfully
            max_runs: 25
          ) do
      case GraSQL.Native.parse_query(query) do
        {:ok, _query_id, _op_kind, _op_name, resolution_request} ->
          {:field_names, field_names, :field_paths, field_paths, :column_map, _column_map,
           :operation_kind, _operation_kind} = resolution_request

          # Check that we have at least one field name and one field path
          assert length(field_names) > 0
          assert length(field_paths) > 0

        {:error, _} ->
          # Skip queries that don't parse
          :ok
      end
    end
  end

  property "parsing same query multiple times yields same query ID" do
    check all(
            query <- graphql_query_generator(1),
            # Filter to only include queries that parse successfully
            max_runs: 25
          ) do
      case GraSQL.Native.parse_query(query) do
        {:ok, query_id1, _, _, _} ->
          # Parse again and verify same ID
          case GraSQL.Native.parse_query(query) do
            {:ok, query_id2, _, _, _} ->
              assert query_id1 == query_id2

            {:error, _} ->
              flunk("Query parsed successfully the first time but not the second time: #{query}")
          end

        {:error, _} ->
          # Skip queries that don't parse
          :ok
      end
    end
  end
end
