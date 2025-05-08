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
          process_operations(operations, variables)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Process SQL operations to include variables
  defp process_operations(operations, variables) do
    Enum.reduce_while(operations, {:ok, []}, fn {name, sql, params}, {:ok, acc} ->
      case process_parameters(params, variables) do
        {:error, _} = err -> {:halt, err}
        processed_params -> {:cont, {:ok, [{name, sql, processed_params} | acc]}}
      end
    end)
    |> case do
      {:ok, ops} -> {:ok, Enum.reverse(ops)}
      err -> err
    end
  end

  # Process parameters to include variable values
  defp process_parameters(params, variables) do
    Enum.reduce_while(params, [], &process_parameter(&1, &2, variables))
    |> case do
      {:error, _} = err -> err
      acc -> Enum.reverse(acc)
    end
  end

  # Process a single parameter
  defp process_parameter({0, value}, acc, _variables), do: {:cont, [value | acc]}

  defp process_parameter({1, var_name}, acc, variables) do
    case lookup_variable(var_name, variables) do
      {:ok, value} -> {:cont, [value | acc]}
      {:error, _} = err -> {:halt, err}
    end
  end

  # Helper function to lookup variable in variables map
  defp lookup_variable(var_name, variables) do
    case Map.fetch(variables, var_name) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        case Map.fetch(variables, String.to_atom(to_string(var_name))) do
          {:ok, value} -> {:ok, value}
          :error -> {:error, {:missing_variable, var_name}}
        end
    end
  end
end
