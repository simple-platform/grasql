defmodule GraSQL.Field do
  @moduledoc """
  Represents a field in a GraphQL query.

  A field is a fundamental building block of GraphQL queries, representing
  data that should be fetched from the schema. Fields can be nested through
  their selection sets, forming the query structure tree.

  ## Memory Usage

  Fields are designed to be memory-efficient, with string names and aliases
  potentially benefiting from interning in large queries with repeated fields.
  Arguments are stored as maps for efficient lookups.

  ## Optimization Opportunities

  - String interning for frequently repeated field names
  - Shared selection set references for identical subqueries
  - Argument map optimization for fields with the same argument patterns
  """

  @typedoc "Field in a GraphQL query"
  @type t :: %__MODULE__{
          name: String.t(),
          alias: String.t() | nil,
          arguments: map(),
          selection: GraSQL.Selection.t(),
          source_position: GraSQL.SourcePosition.t()
        }

  defstruct [:name, :alias, :arguments, :selection, :source_position]

  @doc """
  Creates a new field with the given parameters.

  ## Parameters

  - `name`: The field name in the schema
  - `alias`: Optional field alias in the result
  - `arguments`: Map of arguments for the field
  - `selection`: Selection set for this field
  - `source_position`: Position in the source document

  ## Examples

      iex> selection = GraSQL.Selection.new()
      iex> pos = GraSQL.SourcePosition.new(5, 10)
      iex> GraSQL.Field.new("users", nil, %{limit: 10}, selection, pos)
      %GraSQL.Field{
        name: "users",
        alias: nil,
        arguments: %{limit: 10},
        selection: %GraSQL.Selection{fields: []},
        source_position: %GraSQL.SourcePosition{line: 5, column: 10}
      }
  """
  @spec new(String.t(), String.t() | nil, map(), GraSQL.Selection.t(), GraSQL.SourcePosition.t()) ::
          t()
  def new(name, alias, arguments, selection, source_position) do
    %__MODULE__{
      name: name,
      alias: alias,
      arguments: arguments,
      selection: selection,
      source_position: source_position
    }
  end

  @doc """
  Creates a new leaf field with no selection set.

  ## Parameters

  - `name`: The field name in the schema
  - `alias`: Optional field alias in the result
  - `arguments`: Map of arguments for the field
  - `source_position`: Position in the source document

  ## Examples

      iex> pos = GraSQL.SourcePosition.new(5, 10)
      iex> GraSQL.Field.new_leaf("id", nil, %{}, pos)
      %GraSQL.Field{
        name: "id",
        alias: nil,
        arguments: %{},
        selection: %GraSQL.Selection{fields: []},
        source_position: %GraSQL.SourcePosition{line: 5, column: 10}
      }
  """
  @spec new_leaf(String.t(), String.t() | nil, map(), GraSQL.SourcePosition.t()) :: t()
  def new_leaf(name, alias, arguments, source_position) do
    %__MODULE__{
      name: name,
      alias: alias,
      arguments: arguments,
      selection: GraSQL.Selection.new(),
      source_position: source_position
    }
  end

  @doc """
  Returns the effective name of the field (using alias if present, otherwise name).

  ## Parameters

  - `field`: The field to get the effective name from

  ## Examples

      iex> field = %GraSQL.Field{name: "userId", alias: "id"}
      iex> GraSQL.Field.effective_name(field)
      "id"

      iex> field = %GraSQL.Field{name: "id", alias: nil}
      iex> GraSQL.Field.effective_name(field)
      "id"
  """
  @spec effective_name(t()) :: String.t()
  def effective_name(%__MODULE__{name: name, alias: nil}), do: name
  def effective_name(%__MODULE__{alias: alias}) when not is_nil(alias), do: alias

  @doc """
  Gets the value of an argument from the field, with an optional default value.

  ## Parameters

  - `field`: The field to get the argument from
  - `arg_name`: The name of the argument
  - `default`: Default value to return if argument is not present

  ## Examples

      iex> field = %GraSQL.Field{arguments: %{"limit" => 10}}
      iex> GraSQL.Field.get_argument(field, "limit", 20)
      10

      iex> field = %GraSQL.Field{arguments: %{}}
      iex> GraSQL.Field.get_argument(field, "limit", 20)
      20
  """

  @spec get_argument(t(), String.t(), any()) :: any()
  def get_argument(%__MODULE__{arguments: arguments}, arg_name, default \\ nil) do
    unless is_binary(arg_name) do
      raise ArgumentError, "arg_name must be a string"
    end
    Map.get(arguments, arg_name, default)

  end
end
