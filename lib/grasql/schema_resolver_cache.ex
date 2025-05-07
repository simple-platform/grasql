defmodule GraSQL.SchemaResolverCache do
  @moduledoc """
  Caches the SchemaResolver module to avoid repeated config lookups.

  This module provides a simple cache for the SchemaResolver module using ETS,
  optimizing performance for high-throughput environments.
  """

  use GenServer
  require Logger

  @table_name :grasql_resolver_cache
  @key :schema_resolver

  @doc """
  Starts the SchemaResolverCache GenServer.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Returns the cached SchemaResolver module.

  ## Returns

  * `{:ok, module}` - The resolver module if found
  * `{:error, reason}` - If no resolver is configured
  """
  def get_resolver do
    case :ets.lookup(@table_name, @key) do
      [{@key, resolver}] -> {:ok, resolver}
      [] -> {:error, "Schema resolver not configured"}
    end
  end

  @doc false
  def init(_) do
    # Check if table already exists (for example in tests)
    table =
      case :ets.whereis(@table_name) do
        :undefined ->
          # Create new table
          :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])

        _ ->
          # Table already exists (in tests)
          @table_name
      end

    # Get the resolver from config
    case GraSQL.Config.get_config() do
      {:ok, config} ->
        resolver = config.schema_resolver

        if is_nil(resolver) do
          Logger.error("Schema resolver not configured in application config")
        else
          :ets.insert(table, {@key, resolver})
        end

      {:error, reason} ->
        Logger.error("Failed to load GraSQL config: #{reason}")
    end

    {:ok, %{table: table}}
  end
end
