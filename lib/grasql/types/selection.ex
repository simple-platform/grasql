defmodule GraSQL.Selection do
  @moduledoc """
  Represents a GraphQL selection set.

  A Selection contains a list of fields that are selected
  in a GraphQL query. This structure is used throughout the query tree
  to represent nested selection sets.

  ## Memory Usage

  Selection sets can be large for complex queries, but the structure
  is designed to be memory efficient even with many nested selections.

  ## Traversal Patterns

  Selections are typically traversed depth-first, with each field
  processed in order. This module provides utility functions
  for common traversal operations.
  """

  @typedoc "Selection set containing fields"
  @type t :: %__MODULE__{
          fields: list(GraSQL.Field.t())
        }

  defstruct fields: []

  @doc """
  Creates a new, empty selection set.

  ## Examples

      iex> GraSQL.Selection.new()
      %GraSQL.Selection{fields: []}
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Creates a selection set with the given fields.

  ## Parameters

  - `fields`: List of fields in the selection

  ## Examples

      iex> fields = []
      iex> GraSQL.Selection.new(fields)
      %GraSQL.Selection{fields: []}
  """
  @spec new(list(GraSQL.Field.t())) :: t()
  def new(fields) when is_list(fields) do
    %__MODULE__{
      fields: fields
    }
  end

  @doc """
  Adds a field to the selection set.

  ## Parameters

  - `selection`: The selection set to add to
  - `field`: The field to add

  ## Examples

      iex> selection = GraSQL.Selection.new()
      iex> field = %GraSQL.Field{name: "id"}
      iex> GraSQL.Selection.add_field(selection, field)
      %GraSQL.Selection{fields: [%GraSQL.Field{name: "id"}]}
  """
  @spec add_field(t(), GraSQL.Field.t()) :: t()
  def add_field(%__MODULE__{fields: fields} = selection, field) do
    %{selection | fields: [field | fields]}
  end

  @doc """
  Finds a field by name in the selection set.

  ## Parameters

  - `selection`: The selection set to search
  - `name`: The field name to find

  ## Examples

      iex> selection = %GraSQL.Selection{fields: [%GraSQL.Field{name: "id"}, %GraSQL.Field{name: "name"}]}
      iex> GraSQL.Selection.find_field(selection, "name")
      {:ok, %GraSQL.Field{name: "name"}}

      iex> selection = %GraSQL.Selection{fields: [%GraSQL.Field{name: "id"}]}
      iex> GraSQL.Selection.find_field(selection, "email")
      :error
  """
  @spec find_field(t(), String.t()) :: {:ok, GraSQL.Field.t()} | :error
  def find_field(%__MODULE__{fields: fields}, name) do
    case Enum.find(fields, fn field -> field.name == name end) do
      nil -> :error
      field -> {:ok, field}
    end
  end
end
