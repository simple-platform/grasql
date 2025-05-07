defmodule GraSQL do
  @moduledoc """
  GraSQL is a high-performance GraphQL to SQL compiler.

  This module provides the main entry point for transforming GraphQL queries
  into efficient SQL statements.

  ## Configuration

  GraSQL requires a schema resolver to be configured in your application's
  configuration. The schema resolver is a module that implements the
  `GraSQL.SchemaResolver` behavior.

  ```elixir
  # In your config.exs
  config :grasql,
    schema_resolver: MyApp.SchemaResolver,
    max_query_depth: 15
  ```

  For more configuration options, see `GraSQL.Config`.
  """

  @doc """
  Generate SQL for a GraphQL query.

  ## Parameters

  * `query` - The GraphQL query string
  * `variables` - Map of variables for the query (default: %{})
  * `context` - Optional context for schema resolution (default: %{})

  ## Returns

  * `{:ok, operations}` - List of SQL operations if successful
  * `{:error, reason}` - Error message if generation fails

  ## Examples

      iex> query = "{ users { id name } }"
      iex> GraSQL.generate_sql(query)
      {:ok, [{"users", "SELECT id, name FROM users", []}]}

      iex> GraSQL.generate_sql(query, %{"userId" => 123})
      {:ok, [{"users", "SELECT id, name FROM users WHERE id = $1", [123]}]}
  """
  @spec generate_sql(String.t(), map(), map()) :: {:ok, list()} | {:error, String.t()}
  def generate_sql(query, variables \\ %{}, context \\ %{}) do
    with {:ok, resolution_request} <- GraSQL.Native.parse_query(query) do
      resolution_response = GraSQL.Schema.resolve(resolution_request, context)

      # Generate SQL
      case GraSQL.Native.generate_sql(resolution_response) do
        {:ok, operations} ->
          # Process operations with variables
          processed_operations = process_operations(operations, variables)
          {:ok, processed_operations}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Process SQL operations to include variables
  defp process_operations(operations, variables) do
    Enum.map(operations, fn {name, sql, params} ->
      processed_params = process_parameters(params, variables)
      {name, sql, processed_params}
    end)
  end

  # Process parameters to include variable values
  defp process_parameters(params, variables) do
    Enum.map(params, fn
      # Inline value
      {0, value} ->
        value

      # Variable reference
      {1, var_name} ->
        Map.get(variables, var_name) ||
          Map.get(variables, String.to_atom(var_name))
    end)
  end
end
