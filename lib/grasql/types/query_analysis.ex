defmodule GraSQL.QueryAnalysis do
  @moduledoc """
  Represents the results of analyzing a GraphQL query.

  QueryAnalysis contains the query structure tree, schema needs, variable map,
  and operation type. This information is used during SQL generation to create
  optimized SQL queries.

  ## Memory Usage

  QueryAnalysis contains references to potentially large structures,
  but is designed to share references efficiently rather than duplicating data.
  """

  @typedoc "Results of query analysis"
  @type t :: %__MODULE__{
          qst: GraSQL.QueryStructureTree.t(),
          schema_needs: GraSQL.SchemaNeeds.t(),
          variable_map: map(),
          operation_type: GraSQL.OperationType.t()
        }

  defstruct [:qst, :schema_needs, :variable_map, :operation_type]

  @doc """
  Creates a new query analysis result.

  ## Parameters

  - `qst`: The query structure tree
  - `schema_needs`: The schema needs for the query
  - `variable_map`: Map of variable names to values
  - `operation_type`: The type of GraphQL operation

  ## Examples

      iex> qst = %GraSQL.QueryStructureTree{operation_type: :query}
      iex> schema_needs = GraSQL.SchemaNeeds.new()
      iex> variable_map = %{"limit" => 10}
      iex> operation_type = GraSQL.OperationType.query()
      iex> GraSQL.QueryAnalysis.new(qst, schema_needs, variable_map, operation_type)
      %GraSQL.QueryAnalysis{
        qst: %GraSQL.QueryStructureTree{operation_type: :query, root_fields: [], variables: []},
        schema_needs: %GraSQL.SchemaNeeds{tables: [], relationships: []},
        variable_map: %{"limit" => 10},
        operation_type: :query
      }
  """
  @spec new(
          GraSQL.QueryStructureTree.t(),
          GraSQL.SchemaNeeds.t(),
          map(),
          GraSQL.OperationType.t()
        ) :: t()
  def new(qst, schema_needs, variable_map, operation_type) do
    %__MODULE__{
      qst: qst,
      schema_needs: schema_needs,
      variable_map: variable_map,
      operation_type: operation_type
    }
  end

  @doc """
  Gets the value of a variable from the variable map.

  ## Parameters

  - `analysis`: The query analysis
  - `var_name`: The variable name
  - `default`: Optional default value if variable is not found

  ## Examples

      iex> analysis = %GraSQL.QueryAnalysis{variable_map: %{"limit" => 10}}
      iex> GraSQL.QueryAnalysis.get_variable(analysis, "limit", 20)
      10

      iex> analysis = %GraSQL.QueryAnalysis{variable_map: %{}}
      iex> GraSQL.QueryAnalysis.get_variable(analysis, "limit", 20)
      20
  """
  @spec get_variable(t(), String.t(), any()) :: any()
  def get_variable(%__MODULE__{variable_map: variable_map}, var_name, default \\ nil) do
    Map.get(variable_map, var_name, default)
  end

  @doc """
  Determines if the query is a mutation.

  ## Parameters

  - `analysis`: The query analysis

  ## Examples

      iex> analysis = %GraSQL.QueryAnalysis{operation_type: :mutation}
      iex> GraSQL.QueryAnalysis.mutation?(analysis)
      true

      iex> analysis = %GraSQL.QueryAnalysis{operation_type: :query}
      iex> GraSQL.QueryAnalysis.mutation?(analysis)
      false
  """
  @spec mutation?(t()) :: boolean()
  def mutation?(%__MODULE__{operation_type: operation_type}) do
    operation_type == GraSQL.OperationType.mutation()
  end

  @doc """
  Gets the count of tables needed for this query.

  ## Parameters

  - `analysis`: The query analysis

  ## Examples

      iex> tables = [GraSQL.TableRef.new("public", "users", nil)]
      iex> schema_needs = GraSQL.SchemaNeeds.new(tables, [])
      iex> analysis = %GraSQL.QueryAnalysis{schema_needs: schema_needs}
      iex> GraSQL.QueryAnalysis.table_count(analysis)
      1
  """
  @spec table_count(t()) :: non_neg_integer()
  def table_count(%__MODULE__{schema_needs: schema_needs}) do
    length(schema_needs.tables)
  end
end
