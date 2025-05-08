defmodule GraSQL.Config do
  @moduledoc """
  Configuration for GraSQL's GraphQL to SQL translation process.

  This module defines the configuration struct and validation functions for
  GraSQL's initialization phase. Configuration controls:

  * Naming conventions for fields and parameters
  * Operator mappings between GraphQL and SQL
  * Cache settings for query optimization
  * Performance limits to prevent resource exhaustion

  ## Basic Usage

      # In your application configuration (config/config.exs)
      config :grasql,
        schema_resolver: MyApp.SchemaResolver,
        max_query_depth: 15,
        query_cache_max_size: 500

      # In your application code
      {:ok, config} = GraSQL.Config.load_and_validate()
  """

  # Type Definitions
  #############################################################################

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
  * `aggregate_nodes_field_name` - Field name for nodes in aggregate queries (default: "nodes")

  ### Mutation naming conventions
  * `insert_prefix` - Prefix for insert mutation fields in GraphQL (default: "insert_")
  * `update_prefix` - Prefix for update mutation fields in GraphQL (default: "update_")
  * `delete_prefix` - Prefix for delete mutation fields in GraphQL (default: "delete_")

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
          aggregate_nodes_field_name: String.t(),

          # Mutation naming conventions
          insert_prefix: String.t(),
          update_prefix: String.t(),
          delete_prefix: String.t(),

          # Operator mappings
          operators: %{operator => String.t()},

          # Cache settings
          query_cache_max_size: pos_integer(),
          query_cache_ttl_seconds: non_neg_integer(),

          # Performance settings
          max_query_depth: pos_integer(),
          string_interner_capacity: pos_integer(),

          # Schema resolver
          schema_resolver: module() | nil
        }

  # Default Configuration
  #############################################################################

  defstruct [
    # Naming conventions
    aggregate_field_suffix: "_agg",
    primary_key_argument_name: "id",
    aggregate_nodes_field_name: "nodes",

    # Mutation naming conventions
    insert_prefix: "insert_",
    update_prefix: "update_",
    delete_prefix: "delete_",

    # Operator mappings - using standard GraphQL operator syntax
    operators: %{
      # Logical operators
      and: "_and",
      or: "_or",
      not: "_not",

      # Comparison operators
      eq: "_eq",
      neq: "_neq",
      gt: "_gt",
      lt: "_lt",
      gte: "_gte",
      lte: "_lte",

      # Pattern matching
      like: "_like",
      ilike: "_ilike",

      # Collection operators
      in: "_in",
      nin: "_nin",
      is_null: "_is_null",

      # JSON operators
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

    # Schema resolver
    schema_resolver: nil
  ]

  # Public API
  #############################################################################

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
      {:error, "Cache settings must be: query_cache_max_size > 0, query_cache_ttl_seconds ≥ 0"}
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

      # Configure GraSQL in your config.exs
      config :grasql, schema_resolver: MyApp.SchemaResolver, max_query_depth: 20

      # Load and validate the configuration
      {:ok, config} = GraSQL.Config.load_and_validate()
      config.max_query_depth  # Returns 20
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
      |> Enum.filter(fn {key, _} -> key in config_fields and is_atom(key) end)
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

    # Convert the struct to a map with only the needed keys for Rust
    config
    |> Map.from_struct()
    |> Map.take([
      :aggregate_field_suffix,
      :primary_key_argument_name,
      :aggregate_nodes_field_name,
      :insert_prefix,
      :update_prefix,
      :delete_prefix,
      :operators,
      :query_cache_max_size,
      :query_cache_ttl_seconds,
      :max_query_depth,
      :string_interner_capacity
    ])
    |> Map.put(:operators, string_operators)
  end

  @doc """
  Generates configuration data for NIF loading.

  Called by Rustler when the NIF is loaded. Loads and validates the configuration
  from the application environment and converts it to the native format.

  ## Returns

  * The validated configuration in native format

  ## Examples

      # During application initialization, the configuration is loaded
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

  @doc """
  Loads configuration from application environment for a specific module and validates it.

  This function extends the default configuration system to support module-specific
  configurations, allowing different modules to use different configuration settings.

  ## Parameters

  * `module` - The module to load configuration for (optional)

  ## Returns

  * `{:ok, config}` - If loading and validation are successful
  * `{:error, reason}` - If validation fails, with a descriptive error message

  ## Examples

      # Configure GraSQL in your config.exs
      config :grasql, MyApp.GraphQLAPI,
        max_query_depth: 20,
        schema_resolver: MyApp.SchemaResolver

      # Load and validate the module-specific configuration
      {:ok, config} = GraSQL.Config.load_and_validate_for_module(MyApp.GraphQLAPI)
      config.max_query_depth  # Returns 20
  """
  @spec load_and_validate_for_module(module()) :: {:ok, t()} | {:error, String.t()}
  def load_and_validate_for_module(module) when is_atom(module) do
    # Get base application config (excluding module-specific configs)
    base_config =
      Application.get_all_env(:grasql)
      |> Enum.filter(fn {key, _} -> is_atom(key) end)
      |> Enum.into(%{})

    # Get module-specific config
    module_config =
      Application.get_env(:grasql, module, [])
      |> Enum.into(%{})

    # Merge configurations with module config taking precedence
    merged_config = Map.merge(base_config, module_config)

    # Only include fields that exist in Config struct
    config_fields = __struct__() |> Map.keys() |> Enum.filter(&(&1 != :__struct__))

    # Filter merged_config to only include valid config fields
    valid_config =
      merged_config
      |> Enum.filter(fn {key, _} -> key in config_fields end)
      |> Enum.into(%{})

    # Create config struct with merged settings
    config = struct(__MODULE__, valid_config)

    # Validate the config
    case validate(config) do
      {:ok, validated_config} ->
        # Cache the validated config for this module using an atom key
        config_key = module_config_key(module)
        Application.put_env(:grasql, config_key, validated_config)
        {:ok, validated_config}

      error ->
        error
    end
  end

  @doc """
  Gets the validated configuration for a specific module.

  Retrieves cached configuration if available, otherwise loads and validates.

  ## Parameters

  * `module` - The module to get configuration for

  ## Returns

  * `{:ok, config}` - The validated configuration
  * `{:error, reason}` - If validation fails

  ## Examples

      {:ok, config} = GraSQL.Config.get_config_for(MyApp.GraphQLAPI)
  """
  @spec get_config_for(module()) :: {:ok, t()} | {:error, String.t()}
  def get_config_for(module) when is_atom(module) do
    config_key = module_config_key(module)

    case Application.get_env(:grasql, config_key) do
      nil -> load_and_validate_for_module(module)
      config -> {:ok, config}
    end
  end

  # Helper function to create a unique atom key for module configuration
  defp module_config_key(module) do
    module_name = module |> Atom.to_string() |> String.replace("Elixir.", "")
    :"__config_#{module_name}__"
  end

  @doc """
  Gets the default validated configuration.

  Retrieves cached global configuration if available, otherwise loads and validates.

  ## Returns

  * `{:ok, config}` - The validated configuration
  * `{:error, reason}` - If validation fails

  ## Examples

      {:ok, config} = GraSQL.Config.get_config()
  """
  @spec get_config() :: {:ok, t()} | {:error, String.t()}
  def get_config do
    case Application.get_env(:grasql, :__config__) do
      nil -> load_and_validate()
      config -> {:ok, config}
    end
  end

  # Validation Functions
  #############################################################################

  @doc false
  defp validate_naming_conventions(config) do
    if is_binary(config.aggregate_field_suffix) and
         is_binary(config.primary_key_argument_name) and
         is_binary(config.aggregate_nodes_field_name) and
         is_binary(config.insert_prefix) and
         is_binary(config.update_prefix) and
         is_binary(config.delete_prefix) do
      :ok
    else
      {:error, "Naming convention fields must be strings"}
    end
  end

  @doc false
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

  @doc false
  defp validate_cache_settings(config) do
    if is_integer(config.query_cache_max_size) and config.query_cache_max_size > 0 and
         is_integer(config.query_cache_ttl_seconds) and config.query_cache_ttl_seconds >= 0 do
      :ok
    else
      {:error, "Cache settings must be: query_cache_max_size > 0, query_cache_ttl_seconds ≥ 0"}
    end
  end

  @doc false
  defp validate_performance_settings(config) do
    if is_integer(config.max_query_depth) and config.max_query_depth > 0 and
         is_integer(config.string_interner_capacity) and config.string_interner_capacity > 0 do
      :ok
    else
      {:error, "Performance settings must be positive integers"}
    end
  end

  @doc false
  defp validate_schema_resolver(config) do
    resolver = config.schema_resolver

    cond do
      # Check if resolver is nil
      is_nil(resolver) ->
        {:error, "Schema resolver must be configured. Please set schema_resolver in your config."}

      # In test environment, we allow missing modules as they might be loaded later
      Mix.env() == :test ->
        :ok

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

  @doc false
  defp functions_implemented?(module) do
    required_functions = [
      {:resolve_table, 2},
      {:resolve_relationship, 3},
      {:resolve_columns, 2},
      {:resolve_column_attribute, 4}
    ]

    Enum.all?(
      required_functions,
      &function_exported?(module, elem(&1, 0), elem(&1, 1))
    )
  end
end
