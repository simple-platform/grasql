defmodule GraSQL.Config do
  @moduledoc """
  Configuration for GraSQL's GraphQL to SQL translation process.

  This module defines the configuration struct and validation functions for
  GraSQL's initialization phase. Configuration controls:

  * Naming conventions for fields and parameters
  * Operator mappings between GraphQL and SQL
  * Cache settings for query optimization
  * Performance limits to prevent resource exhaustion
  """

  @typedoc """
  Supported comparison operators in GraphQL queries.

  ## Logical operators
  * `:and` - Logical AND
  * `:or` - Logical OR
  * `:not` - Logical NOT

  ## Comparison operators
  * `:eq` - Equal to
  * `:neq` - Not equal to
  * `:gt` - Greater than
  * `:lt` - Less than
  * `:gte` - Greater than or equal to
  * `:lte` - Less than or equal to

  ## Pattern matching
  * `:like` - SQL LIKE pattern matching
  * `:ilike` - Case-insensitive LIKE pattern matching

  ## Collection operators
  * `:in` - Matches any value in a list
  * `:nin` - Does not match any value in a list
  * `:is_null` - Is NULL check

  ## JSON operators
  * `:json_contains` - JSON containment check (PostgreSQL `@>`)
  * `:json_contained_in` - JSON contained by check (PostgreSQL `<@`)
  * `:json_has_key` - JSON key existence check (PostgreSQL `?`)
  * `:json_has_any_keys` - JSON path existence check (PostgreSQL `?|`)
  * `:json_has_all_keys` - JSON path all existence check (PostgreSQL `?&`)
  * `:json_path` - JSON field access (PostgreSQL `->`)
  * `:json_path_text` - JSON field access as text (PostgreSQL `->>`)
  * `:is_json` - JSON type validation check
  """
  # Logical operators
  @type operator ::
          :and
          | :or
          | :not
          # Comparison operators
          | :eq
          | :neq
          | :gt
          | :lt
          | :gte
          | :lte
          # Pattern matching
          | :like
          | :ilike
          # Collection operators
          | :in
          | :nin
          | :is_null
          # JSON operators
          | :json_contains
          | :json_contained_in
          | :json_has_key
          | :json_has_any_keys
          | :json_has_all_keys
          | :json_path
          | :json_path_text
          | :is_json

  @typedoc """
  Configuration struct for GraSQL.

  ## Fields

  ### Naming conventions
  * `aggregate_field_suffix` - Suffix for aggregate field names in GraphQL
  * `primary_key_argument_name` - Parameter name for single entity queries

  ### Operator mappings
  * `operators` - Map of GraphQL operator suffixes for each operator type

  ### Cache settings
  * `query_cache_max_size` - Maximum number of entries in the query cache
  * `query_cache_ttl_seconds` - Time-to-live for cache entries in seconds
  * `string_interner_capacity` - Maximum number of strings to intern

  ### Performance settings
  * `max_query_depth` - Maximum allowed depth for GraphQL queries

  ### Schema resolution
  * `schema_resolver` - Module that implements the SchemaResolver behavior
  """
  @type t :: %__MODULE__{
          # Naming conventions
          aggregate_field_suffix: String.t(),
          primary_key_argument_name: String.t(),

          # Operator mappings
          operators: %{operator => String.t()},

          # Cache settings
          query_cache_max_size: pos_integer(),
          query_cache_ttl_seconds: non_neg_integer(),

          # Performance settings
          max_query_depth: pos_integer(),
          string_interner_capacity: pos_integer(),

          # Schema resolver
          schema_resolver: module()
        }

  defstruct [
    # Naming conventions
    aggregate_field_suffix: "_agg",
    primary_key_argument_name: "id",

    # Operator mappings - using standard GraphQL operator syntax
    operators: %{
      and: "_and",
      or: "_or",
      not: "_not",
      eq: "_eq",
      neq: "_neq",
      gt: "_gt",
      lt: "_lt",
      gte: "_gte",
      lte: "_lte",
      like: "_like",
      ilike: "_ilike",
      in: "_in",
      nin: "_nin",
      is_null: "_is_null",
      json_contains: "_json_contains",
      json_contained_in: "_json_contained_in",
      json_has_key: "_json_has_key",
      json_has_any_keys: "_json_has_any_keys",
      json_has_all_keys: "_json_has_all_keys",
      json_path: "_json_path",
      json_path_text: "_json_path_text",
      is_json: "_is_json"
    },

    # Cache settings
    query_cache_max_size: 1000,
    query_cache_ttl_seconds: 600,

    # Performance settings
    max_query_depth: 10,
    string_interner_capacity: 10_000,

    # Schema resolver - default to SimpleResolver
    schema_resolver: GraSQL.SimpleResolver
  ]

  @doc """
  Validates a GraSQL configuration.

  Checks configuration values against expected types and constraints.

  ## Parameters

  * `config` - A `GraSQL.Config` struct to validate

  ## Returns

  * `{:ok, config}` - If configuration is valid
  * `{:error, reason}` - If validation fails, with a descriptive error message

  ## Examples

      iex> config = %GraSQL.Config{schema_resolver: GraSQL.SimpleResolver}
      iex> GraSQL.Config.validate(config)
      {:ok, %GraSQL.Config{schema_resolver: GraSQL.SimpleResolver}}

      iex> config = %GraSQL.Config{query_cache_max_size: -1, schema_resolver: GraSQL.SimpleResolver}
      iex> GraSQL.Config.validate(config)
      {:error, "Cache settings must be non-negative integers"}
  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{} = config) do
    validators = [
      &validate_naming_conventions/1,
      &validate_operators/1,
      &validate_cache_settings/1,
      &validate_performance_settings/1,
      &validate_schema_resolver/1
    ]

    Enum.reduce_while(validators, {:ok, config}, fn validator, {:ok, config} ->
      case validator.(config) do
        :ok -> {:cont, {:ok, config}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Loads configuration from application environment and validates it.

  Centralizes loading and validation of GraSQL configuration.

  ## Returns

  * `{:ok, config}` - If loading and validation are successful
  * `{:error, reason}` - If validation fails, with a descriptive error message

  ## Examples

      iex> Application.put_env(:grasql, :max_query_depth, 20)
      iex> {:ok, config} = GraSQL.Config.load_and_validate()
      iex> config.max_query_depth
      20
  """
  @spec load_and_validate() :: {:ok, t()} | {:error, String.t()}
  def load_and_validate do
    # Get all application config
    app_config = Application.get_all_env(:grasql)

    # Only include fields that exist in Config struct
    config_fields = __struct__() |> Map.keys() |> Enum.filter(&(&1 != :__struct__))

    # Filter app_config to only include valid config fields
    valid_config =
      app_config
      |> Enum.filter(fn {key, _} -> key in config_fields end)
      |> Enum.into(%{})

    # Ensure schema_resolver is included if set in application environment
    valid_config =
      case valid_config[:schema_resolver] || app_config[:schema_resolver] do
        nil -> valid_config
        resolver -> Map.put(valid_config, :schema_resolver, resolver)
      end

    # Create config struct with application settings
    config = struct(__MODULE__, valid_config)

    # Validate the config
    validate(config)
  end

  @doc """
  Prepares the config for passing to the Rust NIF.

  Converts the configuration struct to a format compatible with Rust.

  ## Parameters

  * `config` - A valid `GraSQL.Config` struct

  ## Returns

  * A map with the same structure as the input config, but with string operator keys

  ## Examples

      iex> config = %GraSQL.Config{operators: %{eq: "_eq", gt: "_gt"}}
      iex> native_config = GraSQL.Config.to_native_config(config)
      iex> native_config.operators
      %{"eq" => "_eq", "gt" => "_gt"}
  """
  @spec to_native_config(t()) :: map()
  def to_native_config(%__MODULE__{} = config) do
    # Convert atom keys to strings for Rust compatibility
    string_operators = for {k, v} <- config.operators, into: %{}, do: {Atom.to_string(k), v}

    # Convert the entire struct to a plain map
    config
    |> Map.from_struct()
    |> Map.put(:operators, string_operators)
  end

  @doc """
  Generates configuration data for NIF loading.

  Called by Rustler when the NIF is loaded. Loads and validates the configuration
  from the application environment and converts it to the native format.

  ## Returns

  * The validated configuration in native format

  ## Examples

      iex> is_map(GraSQL.Config.load())
      true
  """
  @spec load() :: map()
  def load do
    case load_and_validate() do
      {:ok, valid_config} ->
        # Store the validated config in application env for later retrieval
        Application.put_env(:grasql, :__config__, valid_config)

        # Convert config for Rust NIF
        to_native_config(valid_config)

      {:error, reason} ->
        raise "Failed to generate configuration for GraSQL: #{reason}"
    end
  end

  # Private validation functions

  defp validate_naming_conventions(config) do
    if is_binary(config.aggregate_field_suffix) and
         is_binary(config.primary_key_argument_name) do
      :ok
    else
      {:error, "Naming convention fields must be strings"}
    end
  end

  defp validate_operators(config) do
    if is_map(config.operators) and
         Enum.all?(config.operators, fn {k, v} ->
           is_atom(k) and is_binary(v) and String.starts_with?(v, "_")
         end) do
      :ok
    else
      {:error, "Operators must be a map with atom keys and string values starting with '_'"}
    end
  end

  defp validate_cache_settings(config) do
    if is_integer(config.query_cache_max_size) and config.query_cache_max_size > 0 and
         is_integer(config.query_cache_ttl_seconds) and config.query_cache_ttl_seconds >= 0 do
      :ok
    else
      {:error, "Cache settings must be non-negative integers"}
    end
  end

  defp validate_performance_settings(config) do
    if is_integer(config.max_query_depth) and config.max_query_depth > 0 and
         is_integer(config.string_interner_capacity) and config.string_interner_capacity > 0 do
      :ok
    else
      {:error, "Performance settings must be positive integers"}
    end
  end

  defp validate_schema_resolver(config) do
    # Use SimpleResolver as default if none is configured
    resolver = config.schema_resolver || GraSQL.SimpleResolver

    cond do
      # Ensure the resolver module is loaded
      not Code.ensure_loaded?(resolver) ->
        {:error, "Schema resolver module #{inspect(resolver)} could not be loaded"}

      # Check that all required functions are implemented
      not functions_implemented?(resolver) ->
        {:error, "Schema resolver module must implement required methods"}

      # All checks passed
      true ->
        :ok
    end
  end

  defp functions_implemented?(module) do
    required_functions = [
      {:resolve_table, 2},
      {:resolve_relationship, 3}
    ]

    Enum.all?(
      required_functions,
      &function_exported?(module, elem(&1, 0), elem(&1, 1))
    )
  end
end
