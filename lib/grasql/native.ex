defmodule GraSQL.Native do
  @moduledoc """
  Native (Rust) implementations for GraSQL core functionality.

  This module provides the interface to the Rust NIFs that power GraSQL's
  high-performance GraphQL to SQL compilation. The native functions handle:

  * Parsing and validating GraphQL queries
  * Converting GraphQL queries to optimized SQL
  * Managing internal caching and state

  The Rust implementation offers significant performance advantages for
  computationally intensive tasks like query parsing and SQL generation.

  Note: This module should not be used directly. Instead, use the higher-level
  functions in the `GraSQL` module.
  """
  use Rustler,
    otp_app: :grasql,
    crate: :grasql,
    load_data_fun: {GraSQL.Config, :load}

  @doc """
  Parses a GraphQL query string and returns the query ID.

  Validates the GraphQL syntax and stores the parsed query
  in memory for later use by `generate_sql/3`.

  ## Parameters

  * `query` - The GraphQL query string to parse

  ## Returns

  * `{:ok, query_id, operation_kind, operation_name, resolution_request}`
     - `query_id`: A unique identifier for the parsed query
     - `operation_kind`: The kind of operation (:query, :mutation, or :subscription)
     - `operation_name`: The name of the operation if provided, or empty string
     - `resolution_request`: A tuple containing field names, paths, column map, and operation kind

  * `{:error, reason}` - If parsing fails

  ## Error reasons

  * `"syntax_error"` - The query contains syntax errors
  * `"unsupported_operation"` - The operation type is not supported
  * `"parser_error"` - Other parsing errors
  """
  @spec parse_query(String.t()) ::
          {:ok, String.t(), atom(), String.t(),
           {:field_names, list(String.t()), :field_paths, list(list(integer())), :column_map,
            list({integer(), list(String.t())}), :operation_kind, atom()}}
          | {:error, String.t()}
  def parse_query(query), do: do_parse_query(query)

  @doc """
  Generates SQL from a parsed GraphQL query.

  Takes a query ID (from `parse_query/1`), variables,
  and resolved schema information to generate the corresponding SQL query.

  ## Parameters

  * `query_id` - The query ID returned from `parse_query/1`
  * `variables` - A map of GraphQL variables used in the query (default: `%{}`)
  * `schema` - Resolved schema information from GraSQL.Schema.resolve/3

  ## Returns

  * `{:ok, sql, params}`
     - `sql`: The generated SQL query string
     - `params`: A list of parameter values to be used with the SQL query

  * `{:error, reason}` - If SQL generation fails

  ## Error reasons

  * `"query_not_found"` - The specified query ID doesn't exist
  * `"invalid_variables"` - The provided variables are invalid
  * `"compilation_error"` - Error during SQL compilation
  * `"missing_schema_info"` - Required schema information is missing
  """
  @spec generate_sql(String.t(), map(), map() | nil) ::
          {:ok, String.t(), list()} | {:error, String.t()}
  def generate_sql(query_id, variables \\ %{}, schema \\ nil),
    do: do_generate_sql(query_id, variables, schema)

  # These functions are implemented natively in Rust
  @doc false
  @spec do_parse_query(String.t()) ::
          {:ok, String.t(), atom(), String.t(),
           {:field_names, list(String.t()), :field_paths, list(list(integer())), :column_map,
            list({integer(), list(String.t())}), :operation_kind, atom()}}
          | {:error, String.t()}
  def do_parse_query(_query), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  @spec do_generate_sql(String.t(), map(), map() | nil) ::
          {:ok, String.t(), list()} | {:error, String.t()}
  def do_generate_sql(_query_id, _variables, _schema), do: :erlang.nif_error(:nif_not_loaded)
end
