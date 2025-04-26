defmodule GraSQL.SqlResult do
  @moduledoc """
  Represents the SQL query generated from a GraphQL query.

  SqlResult contains the SQL string, parameters, parameter types,
  and the structure of the expected result. This information is used
  to execute the SQL query and map the results back to GraphQL.

  ## Memory Usage

  SQL results can contain large SQL strings, but the structure
  is designed to efficiently represent and process the data.

  ## Parameter Handling

  Parameters are separated from the SQL string for security and
  performance. This allows proper parameter binding in the database
  driver, preventing SQL injection and enabling query plan caching.
  """

  @typedoc "SQL query result"
  @type t :: %__MODULE__{
          sql: String.t(),
          parameters: list(any()),
          parameter_types: list(String.t()),
          result_structure: GraSQL.ResultStructure.t()
        }

  defstruct [:sql, :parameters, :parameter_types, :result_structure]

  @doc """
  Creates a new SQL result.

  ## Parameters

  - `sql`: The SQL query string
  - `parameters`: List of parameter values
  - `parameter_types`: List of parameter type names
  - `result_structure`: Structure of the expected result

  ## Examples

      iex> sql = "SELECT id, name FROM users WHERE id = $1"
      iex> parameters = [1]
      iex> parameter_types = ["integer"]
      iex> result_structure = GraSQL.ResultStructure.new()
      iex> GraSQL.SqlResult.new(sql, parameters, parameter_types, result_structure)
      %GraSQL.SqlResult{
        sql: "SELECT id, name FROM users WHERE id = $1",
        parameters: [1],
        parameter_types: ["integer"],
        result_structure: %GraSQL.ResultStructure{fields: [], nested_objects: %{}}
      }
  """
  @spec new(String.t(), list(any()), list(String.t()), GraSQL.ResultStructure.t()) :: t()
  def new(sql, parameters, parameter_types, result_structure) do
    %__MODULE__{
      sql: sql,
      parameters: parameters,
      parameter_types: parameter_types,
      result_structure: result_structure
    }
  end

  @doc """
  Adds a parameter to the SQL result.

  ## Parameters

  - `sql_result`: The SQL result
  - `value`: The parameter value
  - `type`: The parameter type name

  ## Examples

      iex> sql_result = %GraSQL.SqlResult{
      ...>   sql: "SELECT * FROM users WHERE id = $1",
      ...>   parameters: [],
      ...>   parameter_types: []
      ...> }
      iex> GraSQL.SqlResult.add_parameter(sql_result, 1, "integer")
      %GraSQL.SqlResult{
        sql: "SELECT * FROM users WHERE id = $1",
        parameters: [1],
        parameter_types: ["integer"]
      }
  """
  @spec add_parameter(t(), any(), String.t()) :: t()
  def add_parameter(
        %__MODULE__{parameters: params, parameter_types: types} = sql_result,
        value,
        type
      ) do
    %{
      sql_result
      | parameters: params ++ [value],
        parameter_types: types ++ [type]
    }
  end

  @doc """
  Gets the parameter count for this SQL result.

  ## Parameters

  - `sql_result`: The SQL result

  ## Examples

      iex> sql_result = %GraSQL.SqlResult{parameters: [1, "test"], parameter_types: ["integer", "text"]}
      iex> GraSQL.SqlResult.parameter_count(sql_result)
      2
  """
  @spec parameter_count(t()) :: non_neg_integer()
  def parameter_count(%__MODULE__{parameters: params}) do
    length(params)
  end

  @doc """
  Gets the parameter value at the specified index.

  ## Parameters

  - `sql_result`: The SQL result
  - `index`: The parameter index (0-based)

  ## Examples

      iex> sql_result = %GraSQL.SqlResult{parameters: [1, "test"]}
      iex> GraSQL.SqlResult.get_parameter(sql_result, 1)
      "test"
  """
  @spec get_parameter(t(), non_neg_integer()) :: any()
  def get_parameter(%__MODULE__{parameters: params}, index) do
    Enum.at(params, index)
  end

  @doc """
  Gets the parameter type at the specified index.

  ## Parameters

  - `sql_result`: The SQL result
  - `index`: The parameter index (0-based)

  ## Examples

      iex> sql_result = %GraSQL.SqlResult{parameter_types: ["integer", "text"]}
      iex> GraSQL.SqlResult.get_parameter_type(sql_result, 1)
      "text"
  """
  @spec get_parameter_type(t(), non_neg_integer()) :: String.t()
  def get_parameter_type(%__MODULE__{parameter_types: types}, index) do
    Enum.at(types, index)
  end
end
