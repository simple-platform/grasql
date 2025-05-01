defmodule GraSQL.Native do
  @moduledoc """
  Native (Rust) implementations for GraSQL.

  This module provides the interface to the Rust NIFs that power GraSQL's
  high-performance GraphQL to SQL compilation. The native functions handle:

  * Parsing and validating GraphQL queries
  * Converting GraphQL queries to optimized SQL
  * Managing internal caching and state

  The Rust implementation offers significant performance advantages for
  computationally intensive tasks like query parsing and SQL generation.

  Note: This module should not be used directly. Instead, use the higher-level
  functions in the `GraSQL` module, which provide proper validation and error handling.
  """
  use Rustler, otp_app: :grasql, crate: "grasql"

  @doc """
  Initializes the native components with the provided configuration.

  This function must be called before using any other functions in this module.
  It sets up the internal state and configuration for the Rust NIF.

  ## Parameters

    * `config` - A validated configuration map (from `GraSQL.Config.to_native_config/1`)

  ## Returns

    * `:ok` - If initialization is successful
    * `{:error, reason}` - If initialization fails

  ## Error reasons

    * `"invalid_config"` - The provided configuration is invalid
    * `"init_failed"` - Native initialization failed for another reason
  """
  def init(config), do: do_init(config)

  @doc """
  Parses a GraphQL query string and returns the query ID.

  This function validates the GraphQL syntax and stores the parsed query
  in memory for later use by `generate_sql/2`.

  ## Parameters

    * `query` - The GraphQL query string to parse

  ## Returns

    * `{:ok, query_id, operation_kind, operation_name}`
       - `query_id`: A unique identifier for the parsed query
       - `operation_kind`: The kind of operation (:query, :mutation, or :subscription)
       - `operation_name`: The name of the operation if provided, or empty string

    * `{:error, reason}` - If parsing fails

  ## Error reasons

    * `"syntax_error"` - The query contains syntax errors
    * `"unsupported_operation"` - The operation type is not supported
    * `"parser_error"` - Other parsing errors
  """
  def parse_query(query), do: do_parse_query(query)

  @doc """
  Generates SQL from a parsed GraphQL query.

  This function takes a query ID (from `parse_query/1`) and variables,
  and generates the corresponding SQL query and parameterized values.

  ## Parameters

    * `query_id` - The query ID returned from `parse_query/1`
    * `variables` - A map of GraphQL variables used in the query (default: `%{}`)

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
  def generate_sql(query_id, variables \\ %{}), do: do_generate_sql(query_id, variables)

  # These functions are implemented natively in Rust
  def do_init(_config), do: :erlang.nif_error(:nif_not_loaded)

  def do_parse_query(_query), do: :erlang.nif_error(:nif_not_loaded)

  def do_generate_sql(_query_id, _variables), do: :erlang.nif_error(:nif_not_loaded)
end
