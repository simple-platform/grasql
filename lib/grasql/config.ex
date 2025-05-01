defmodule GraSQL.Config do
  @moduledoc """
  Configuration options for GraSQL.

  This module defines the configuration struct and validation functions for
  GraSQL's initialization phase. The configuration controls various aspects of
  the GraphQL to SQL translation process, including:

  * Naming conventions for fields and parameters
  * Operator mappings between GraphQL and SQL
  * Cache settings for query optimization
  * Join behavior for relationship handling
  * Performance limits to prevent resource exhaustion

  Use this module to customize GraSQL's behavior to match your application's needs.
  """

  @typedoc """
  Supported comparison operators in GraphQL queries.

  * `:eq` - Equal to
  * `:neq` - Not equal to
  * `:gt` - Greater than
  * `:lt` - Less than
  * `:gte` - Greater than or equal to
  * `:lte` - Less than or equal to
  * `:like` - SQL LIKE pattern matching
  * `:ilike` - Case-insensitive LIKE pattern matching
  * `:in` - Matches any value in a list
  * `:nin` - Does not match any value in a list
  * `:is_null` - Is NULL check
  """
  @type operator :: :eq | :neq | :gt | :lt | :gte | :lte | :like | :ilike | :in | :nin | :is_null

  @typedoc """
  Configuration struct for GraSQL.

  ## Fields

  ### Naming conventions
  * `aggregate_field_suffix` - Suffix for aggregate field names in GraphQL
  * `single_query_param_name` - Parameter name for single entity queries

  ### Operator mappings
  * `operators` - Map of GraphQL operator suffixes for each operator type

  ### Cache settings
  * `max_cache_size` - Maximum number of entries in the query cache
  * `cache_ttl` - Time-to-live for cache entries in seconds

  ### Join settings
  * `default_join_type` - Default join type (`:inner` or `:left_outer`)
  * `skip_join_table` - Whether to skip intermediate join tables when possible

  ### Performance settings
  * `max_query_depth` - Maximum allowed depth for GraphQL queries
  """
  @type t :: %__MODULE__{
          # Naming conventions
          aggregate_field_suffix: String.t(),
          single_query_param_name: String.t(),

          # Operator mappings
          operators: %{operator => String.t()},

          # Cache settings
          max_cache_size: non_neg_integer(),
          cache_ttl: non_neg_integer(),

          # Join settings
          default_join_type: :inner | :left_outer,
          skip_join_table: boolean(),

          # Performance settings
          max_query_depth: non_neg_integer()
        }

  defstruct [
    # Naming conventions
    aggregate_field_suffix: "_agg",
    single_query_param_name: "id",

    # Operator mappings - using standard GraphQL operator syntax
    operators: %{
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
      is_null: "_is_null"
    },

    # Cache settings
    max_cache_size: 1000,
    cache_ttl: 3600,

    # Join settings
    default_join_type: :left_outer,
    skip_join_table: true,

    # Performance settings
    max_query_depth: 10
  ]

  @doc """
  Validates a GraSQL configuration.

  This function checks all configuration values against their expected types and
  constraints to ensure the configuration is valid before initialization.

  ## Parameters

    * `config` - A `GraSQL.Config` struct to validate

  ## Returns

    * `{:ok, config}` - If the configuration is valid
    * `{:error, reason}` - If validation fails, with a descriptive error message

  ## Examples

      iex> GraSQL.Config.validate(%GraSQL.Config{})
      {:ok, %GraSQL.Config{}}

      iex> GraSQL.Config.validate(%GraSQL.Config{max_cache_size: -1})
      {:error, "Cache settings must be positive integers"}

      iex> GraSQL.Config.validate(%GraSQL.Config{default_join_type: :full})
      {:error, "Join settings are invalid"}
  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{} = config) do
    validators = [
      &validate_naming_conventions/1,
      &validate_operators/1,
      &validate_cache_settings/1,
      &validate_join_settings/1,
      &validate_performance_settings/1
    ]

    Enum.reduce_while(validators, {:ok, config}, fn validator, {:ok, config} ->
      case validator.(config) do
        :ok -> {:cont, {:ok, config}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Prepares the config for passing to the Rust NIF.

  Converts the configuration struct to a format compatible with the Rust native
  implementation, including converting atom keys to strings in the operators map.

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

    # Return a new config map with the string operators
    %{config | operators: string_operators}
  end

  # Private validation functions

  defp validate_naming_conventions(config) do
    if is_binary(config.aggregate_field_suffix) and
         is_binary(config.single_query_param_name) do
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
    if is_integer(config.max_cache_size) and config.max_cache_size > 0 and
         is_integer(config.cache_ttl) and config.cache_ttl >= 0 do
      :ok
    else
      {:error, "Cache settings must be positive integers"}
    end
  end

  defp validate_join_settings(config) do
    if config.default_join_type in [:inner, :left_outer] and
         is_boolean(config.skip_join_table) do
      :ok
    else
      {:error, "Join settings are invalid"}
    end
  end

  defp validate_performance_settings(config) do
    if is_integer(config.max_query_depth) and config.max_query_depth > 0 do
      :ok
    else
      {:error, "Performance settings must be positive integers"}
    end
  end
end
