defmodule GraSQL do
  @moduledoc """
  GraSQL - GraphQL to SQL transpiler.

  This module provides the main interface for converting GraphQL queries to SQL.
  It handles:

  * Parsing of GraphQL queries
  * Generation of SQL queries with parameterized values
  * Integration with schema resolvers for database metadata

  ## Basic Usage

  ```elixir
  # GraSQL is automatically initialized during NIF loading

  # Define a resolver for your database schema
  defmodule MyApp.SchemaResolver do
    @behaviour GraSQL.SchemaResolver

    def resolve_table(table, _ctx), do: table
    def resolve_relationship(rel, _ctx), do: rel
  end

  # Configure the resolver in your config.exs
  config :grasql,
    schema_resolver: MyApp.SchemaResolver

  # Convert a GraphQL query to SQL
  query = "query { users { id name posts { title } } }"
  variables = %{"limit" => 10}

  {:ok, sql, params} = GraSQL.generate_sql(query, variables)

  # Execute the SQL with your database library
  MyApp.Repo.query(sql, params)
  ```

  ## Configuration

  GraSQL is configured through application environment variables in your config.exs:

  ```elixir
  config :grasql,
    query_cache_max_size: 2000,
    max_query_depth: 15,
    schema_resolver: MyApp.SchemaResolver
  ```

  See `GraSQL.Config` module for all available configuration options.
  """

  alias GraSQL.Native

  @doc """
  Parse a GraphQL query string.

  This function validates the GraphQL syntax and returns metadata about the query.
  The returned query_id is used in subsequent calls to generate_sql/3.

  ## Parameters

    * `query` - The GraphQL query string to parse

  ## Returns

    * `{:ok, query_id, operation_kind, operation_name, resolution_request}`
      * `query_id` - A unique identifier for the parsed query
      * `operation_kind` - The type of operation (`:query`, `:mutation`, or `:subscription`)
      * `operation_name` - The name of the operation if present, or an empty string
      * `resolution_request` - A map containing field names and paths that need resolution

    * `{:error, reason}` - If parsing fails

  ## Examples

      # Parse a simple unnamed query
      iex> {:ok, _id, kind, name, _req} = GraSQL.parse_query("query { users { id } }")
      iex> {kind, name}
      {:query, ""}

      # Parse a named query
      iex> {:ok, _id, kind, name, _req} = GraSQL.parse_query("query GetUsers { users { id } }")
      iex> {kind, name}
      {:query, "GetUsers"}

      # Error handling
      iex> result = GraSQL.parse_query("query { invalid syntax")
      iex> match?({:error, _}, result)
      true
  """
  @spec parse_query(String.t()) ::
          {:ok, String.t(), atom(), String.t(), map()} | {:error, String.t()}
  def parse_query(query) do
    case Native.parse_query(query) do
      {:ok, query_id, operation_kind, operation_name, resolution_request} ->
        {:ok, query_id, operation_kind, operation_name, resolution_request}

      {:error, reason} when is_binary(reason) ->
        {:error, reason |> String.trim()}

      error ->
        error
    end
  end

  @doc """
  Generate SQL from a GraphQL query.

  This function takes a GraphQL query and variables, and generates the corresponding SQL query
  with parameterized values using the configured resolver.

  ## Parameters

    * `query` - The GraphQL query string
    * `variables` - A map of GraphQL variables used in the query
    * `ctx` - Context map passed to resolver functions (default: `%{}`)
    * `options` - Additional options for SQL generation (default: `%{}`)

  ## Returns

    * `{:ok, sql, params}`
      * `sql` - The generated SQL query string
      * `params` - A list of parameter values to be used with the SQL query

    * `{:error, reason}` - If SQL generation fails

  ## Examples

      # Generate SQL for a simple query
      iex> query = "query { users { id name } }"
      iex> {:ok, _query_id, _kind, _name, _req} = GraSQL.parse_query(query)
      iex> match?({:ok, _, _}, GraSQL.generate_sql(query, %{}))
      true

      # Using variables
      iex> query = "query($id: ID!) { user(id: $id) { name } }"
      iex> result = GraSQL.generate_sql(query, %{"id" => 123})
      iex> match?({:ok, _, _}, result)
      true

      # Error handling
      iex> result = GraSQL.generate_sql("invalid", %{})
      iex> match?({:error, _}, result)
      true
  """
  @spec generate_sql(String.t(), map(), map(), map()) ::
          {:ok, String.t(), list()} | {:error, String.t()}
  def generate_sql(query, variables, _ctx \\ %{}, _options \\ %{}) do
    # Get the pre-validated config from application environment
    config = get_current_config()

    # All validation is now done during application startup or Config.reload_with_resolver
    with {:ok, query_id, _, _, _resolution_request} <- parse_query(query) do
      # Process the resolution_request through Schema Resolver
      _schema_resolver = config.schema_resolver

      case Native.generate_sql(query_id, variables) do
        {:ok, sql, params} ->
          # Extract values from variables and add to params
          actual_params =
            variables
            |> Map.values()
            |> Enum.concat(params)

          {:ok, sql, actual_params}

        error ->
          error
      end
    end
  end

  # Private helpers

  defp get_current_config do
    # Get the validated configuration struct that was stored during application startup
    # or explicitly loaded via Config.reload_with_resolver
    Application.get_env(:grasql, :__config__) ||
      raise "GraSQL configuration not found. Application may not have been properly initialized."
  end
end
