defmodule GraSQL.QueryStructureTree do
  @moduledoc """
  Represents the structure of a GraphQL query.

  QueryStructureTree contains the parsed structure of a GraphQL query,
  including operation type, root fields, and variables.
  This structure is used during query analysis and SQL generation.

  ## Memory Usage

  For large queries, the QueryStructureTree can contain many nested
  structures. Memory scaling is designed to be linear with the complexity
  of the query. String interning is recommended for variable names
  that are repeated throughout the query.
  """

  @typedoc "GraphQL variable"
  @type variable :: %{
          name: String.t(),
          type: String.t(),
          default_value: any() | nil
        }

  @typedoc "Structure tree of a GraphQL query"
  @type t :: %__MODULE__{
          operation_type: GraSQL.OperationType.t(),
          root_fields: list(GraSQL.Field.t()),
          variables: list(variable())
        }

  defstruct [
    :operation_type,
    root_fields: [],
    variables: []
  ]

  @doc """
  Creates a new query structure tree.

  ## Parameters

  - `operation_type`: The type of GraphQL operation
  - `root_fields`: List of root fields in the query
  - `variables`: List of variables defined in the query

  ## Examples

      iex> op_type = GraSQL.OperationType.query()
      iex> root_fields = []
      iex> variables = []
      iex> GraSQL.QueryStructureTree.new(op_type, root_fields, variables)
      %GraSQL.QueryStructureTree{
        operation_type: :query,
        root_fields: [],
        variables: []
      }
  """
  @spec new(GraSQL.OperationType.t(), list(GraSQL.Field.t()), list(variable())) :: t()
  def new(operation_type, root_fields, variables) do
    %__MODULE__{
      operation_type: operation_type,
      root_fields: root_fields,
      variables: variables
    }
  end

  @doc """
  Adds a root field to the query structure tree.

  ## Parameters

  - `qst`: The query structure tree
  - `field`: The field to add

  ## Examples

      iex> qst = %GraSQL.QueryStructureTree{operation_type: :query, root_fields: []}
      iex> pos = GraSQL.SourcePosition.new(1, 1)
      iex> selection = GraSQL.Selection.new()
      iex> field = GraSQL.Field.new("users", nil, %{}, selection, pos)
      iex> GraSQL.QueryStructureTree.add_root_field(qst, field)
      %GraSQL.QueryStructureTree{
        operation_type: :query,
        root_fields: [
          %GraSQL.Field{
            name: "users",
            alias: nil,
            arguments: %{},
            selection: %GraSQL.Selection{fields: []},
            source_position: %GraSQL.SourcePosition{line: 1, column: 1}
          }
        ],
        variables: []
      }
  """
  @spec add_root_field(t(), GraSQL.Field.t()) :: t()
  def add_root_field(%__MODULE__{root_fields: root_fields} = qst, field) do
    %{qst | root_fields: [field | root_fields]}
  end

  @doc """
  Adds a variable to the query structure tree.

  ## Parameters

  - `qst`: The query structure tree
  - `name`: The variable name
  - `type`: The variable type
  - `default_value`: Optional default value

  ## Examples

      iex> qst = %GraSQL.QueryStructureTree{operation_type: :query, variables: []}
      iex> GraSQL.QueryStructureTree.add_variable(qst, "limit", "Int", 10)
      %GraSQL.QueryStructureTree{
        operation_type: :query,
        root_fields: [],
        variables: [%{name: "limit", type: "Int", default_value: 10}]
      }
  """
  @spec add_variable(t(), String.t(), String.t(), any() | nil) :: t()
  def add_variable(%__MODULE__{variables: variables} = qst, name, type, default_value) do
    variable = %{
      name: name,
      type: type,
      default_value: default_value
    }

    %{qst | variables: [variable | variables]}
  end
end
