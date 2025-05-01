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
  # GraSQL is automatically initialized at application startup

  # Define a resolver for your database schema
  defmodule MyApp.SchemaResolver do
    @behaviour GraSQL.SchemaResolver

    def resolve_table(table, _ctx), do: table
    def resolve_relationship(rel, _ctx), do: rel
  end

  # Convert a GraphQL query to SQL
  query = "query { users { id name posts { title } } }"
  variables = %{"limit" => 10}

  {:ok, sql, params} = GraSQL.generate_sql(query, variables, MyApp.SchemaResolver)

  # Execute the SQL with your database library
  MyApp.Repo.query(sql, params)
  ```

  ## Configuration

  GraSQL is configured through application environment variables in your config.exs:

  ```elixir
  config :grasql,
    max_cache_size: 2000,
    max_query_depth: 15
  ```

  See `GraSQL.Config` module for all available configuration options.
  """

  alias GraSQL.Native

  @doc """
  Parse a GraphQL query string.

  This function validates the GraphQL syntax and returns metadata about the query.
  The returned query_id is used in subsequent calls to generate_sql/5.

  ## Parameters

    * `query` - The GraphQL query string to parse

  ## Returns

    * `{:ok, query_id, operation_kind, operation_name}`
      * `query_id` - A unique identifier for the parsed query
      * `operation_kind` - The type of operation (`:query`, `:mutation`, or `:subscription`)
      * `operation_name` - The name of the operation if present, or an empty string

    * `{:error, reason}` - If parsing fails

  ## Examples

      # Parse a simple unnamed query
      iex> {:ok, _id, kind, name} = GraSQL.parse_query("query { users { id } }")
      iex> {kind, name}
      {:query, ""}

      # Parse a named query
      iex> {:ok, _id, kind, name} = GraSQL.parse_query("query GetUsers { users { id } }")
      iex> {kind, name}
      {:query, "GetUsers"}

      # Error handling
      iex> result = GraSQL.parse_query("query { invalid syntax")
      iex> match?({:error, _}, result)
      true
  """
  @spec parse_query(String.t()) ::
          {:ok, String.t(), atom(), String.t()} | {:error, String.t()}
  def parse_query(query) do
    case Native.parse_query(query) do
      {:ok, query_id, operation_kind, operation_name} ->
        {:ok, query_id, operation_kind, operation_name}

      {:error, reason} when is_binary(reason) ->
        {:error, reason |> String.trim()}

      error ->
        error
    end
  end

  @doc """
  Generate SQL from a GraphQL query.

  This function takes a GraphQL query, variables, and a schema resolver,
  and generates the corresponding SQL query with parameterized values.

  ## Parameters

    * `query` - The GraphQL query string
    * `variables` - A map of GraphQL variables used in the query
    * `resolver` - A module implementing the `GraSQL.SchemaResolver` behaviour
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
      iex> {:ok, _query_id, _kind, _name} = GraSQL.parse_query(query)
      iex> match?({:ok, _, _}, GraSQL.generate_sql(query, %{}, GraSQL.SimpleResolver))
      true

      # Using variables
      iex> query = "query($id: ID!) { user(id: $id) { name } }"
      iex> result = GraSQL.generate_sql(query, %{"id" => 123}, GraSQL.SimpleResolver)
      iex> match?({:ok, _, _}, result)
      true

      # Error handling
      iex> result = GraSQL.generate_sql("invalid", %{}, GraSQL.SimpleResolver)
      iex> match?({:error, _}, result)
      true
  """
  @spec generate_sql(String.t(), map(), module(), map(), map()) ::
          {:ok, String.t(), list()} | {:error, String.t()}
  def generate_sql(query, variables, resolver, _ctx \\ %{}, _options \\ %{}) do
    with :ok <- validate_resolver(resolver),
         {:ok, query_id, _, _} <- parse_query(query) do
      # This would normally call resolve_tables and resolve_relationships
      # before generating SQL, but that's for future implementation
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

  defp validate_resolver(resolver) do
    required_functions = [
      {:resolve_table, 2},
      {:resolve_relationship, 2}
    ]

    case Enum.all?(required_functions, &function_exported?(resolver, elem(&1, 0), elem(&1, 1))) do
      true -> :ok
      false -> {:error, "Resolver module must implement required methods"}
    end
  end
end
