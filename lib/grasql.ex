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
  # Define a resolver for your database schema
  defmodule MyApp.SchemaResolver do
    use GraSQL.SchemaResolver

    @impl true
    def resolve_table(field_name, _ctx) do
      %GraSQL.Schema.Table{schema: "public", name: field_name}
    end

    @impl true
    def resolve_relationship(field_name, parent_table, _ctx) do
      # Simple resolver that assumes foreign key convention
      target_table = %GraSQL.Schema.Table{schema: "public", name: field_name}

      %GraSQL.Schema.Relationship{
        source_table: parent_table,
        target_table: target_table,
        source_columns: ["id"],
        target_columns: ["parent_id"],
        type: :has_many,
        join_table: nil
      }
    end
  end

  # Configure the resolver in your config.exs
  config :grasql, schema_resolver: MyApp.SchemaResolver

  # Convert a GraphQL query to SQL
  query = "query { users { id name posts { title } } }"
  variables = %{"limit" => 10}

  {:ok, sql, params} = GraSQL.generate_sql(query, variables)

  # Execute the SQL with your database library
  MyApp.Repo.query!(sql, params)
  ```

  See `GraSQL.Config` module for all available configuration options.
  """

  alias GraSQL.Native

  # Public API
  #############################################################################

  @doc """
  Parse a GraphQL query string.

  Validates the GraphQL syntax and returns metadata about the query.
  The returned query_id is used in subsequent calls to generate_sql/3.

  ## Parameters

  * `query` - The GraphQL query string to parse

  ## Returns

  * `{:ok, query_id, operation_kind, operation_name, resolution_request}`
    * `query_id` - A unique identifier for the parsed query
    * `operation_kind` - The type of operation (`:query`, `:mutation`, or `:subscription`)
    * `operation_name` - The name of the operation if present, or an empty string
    * `resolution_request` - Information needed for schema resolution

  * `{:error, reason}` - If parsing fails, with a detailed error message

  ## Examples

      # Parse a simple query
      iex> {:ok, _id, kind, name, _req} = GraSQL.parse_query("query { users { id } }")
      iex> {kind, name}
      {:query, ""}

      # Parse a named query
      iex> {:ok, _id, kind, name, _req} = GraSQL.parse_query("query GetUsers { users { id } }")
      iex> {kind, name}
      {:query, "GetUsers"}

      # Handle syntax errors
      iex> {:error, error_message} = GraSQL.parse_query("query { invalid syntax")
      iex> String.contains?(error_message, "Syntax Error")
      true
  """
  @spec parse_query(String.t()) ::
          {:ok, String.t(), atom(), String.t(),
           {:field_names, list(String.t()), :field_paths, list(list(integer())), :column_map,
            list({integer(), list(String.t())}), :operation_kind, atom()}}
          | {:error, String.t()}
  def parse_query(query) do
    case Native.parse_query(query) do
      {:error, reason} when is_binary(reason) -> {:error, reason |> String.trim()}
      result -> result
    end
  end

  @doc """
  Generate SQL from a GraphQL query.

  Takes a GraphQL query and variables, and generates the corresponding SQL query
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

  * `{:error, reason}` - If SQL generation fails, with a detailed error message

  ## Examples

      # Basic query without variables
      iex> query = "query { users { id name } }"
      iex> {:ok, sql, params} = GraSQL.generate_sql(query, %{})
      iex> is_list(params)
      true
      iex> String.contains?(sql, "SELECT")
      true

      # Query with variables
      iex> query = "query($id: ID!) { user(id: $id) { name } }"
      iex> {:ok, sql, params} = GraSQL.generate_sql(query, %{"id" => 123})
      iex> 123 in params
      true
      iex> String.contains?(sql, "WHERE")
      true

      # Handle invalid query
      iex> {:error, error_message} = GraSQL.generate_sql("invalid", %{})
      iex> String.contains?(error_message, "Syntax Error")
      true
  """
  @spec generate_sql(String.t(), map(), map(), map()) ::
          {:ok, String.t(), list()} | {:error, String.t()}
  def generate_sql(query, variables, ctx \\ %{}, _options \\ %{}) do
    # Get the pre-validated config from application environment
    config = get_current_config()
    resolver_module = config.schema_resolver

    with {:ok, query_id, _operation_kind, _operation_name, resolution_request} <-
           parse_query(query),
         {:ok, schema} <- safe_resolve_schema(resolution_request, resolver_module, ctx) do
      # SQL Generation
      case Native.generate_sql(query_id, variables, schema) do
        {:ok, sql, params} ->
          # Extract values from variables and add to params
          actual_params =
            variables
            |> Map.values()
            |> Enum.concat(params)

          {:ok, sql, actual_params}

        {:error, reason} when is_binary(reason) ->
          {:error, String.trim(reason)}
      end
    end
  end

  # Private Helper Functions
  #############################################################################

  @doc false
  @spec safe_resolve_schema(tuple() | map(), module(), map()) ::
          {:ok, map()} | {:error, String.t()}
  defp safe_resolve_schema(resolution_request, resolver_module, ctx) do
    schema = GraSQL.Schema.resolve(resolution_request, resolver_module, ctx)
    {:ok, schema}
  rescue
    e in RuntimeError ->
      {:error, "Schema resolution error: #{Exception.message(e)}"}

    e in KeyError ->
      {:error, "Schema resolution error: Invalid field reference - #{Exception.message(e)}"}

    e in ArgumentError ->
      {:error, "Schema resolution error: Invalid argument - #{Exception.message(e)}"}

    e ->
      {:error, "Unexpected schema resolution error: #{inspect(e)}"}
  catch
    :throw, value ->
      {:error, "Schema resolution error (thrown value): #{inspect(value)}"}

    :exit, value ->
      {:error, "Schema resolution error (exit): #{inspect(value)}"}

    kind, value ->
      {:error, "Schema resolution error (#{kind}): #{inspect(value)}"}
  end

  @doc false
  @spec get_current_config() :: GraSQL.Config.t()
  defp get_current_config do
    # Get the validated configuration struct that was stored during application startup
    Application.get_env(:grasql, :__config__) ||
      raise "GraSQL configuration not found. Application may not have been properly initialized."
  end
end
