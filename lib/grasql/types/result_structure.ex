defmodule GraSQL.ResultStructure do
  @moduledoc """
  Describes the structure of SQL query results.

  ResultStructure maps SQL query results to GraphQL response structures,
  describing how the flat SQL results should be reconstructed into the
  nested GraphQL response format.

  ## Memory Usage

  Result structures are designed to be memory-efficient, with field path
  references potentially benefiting from interning in large queries.
  """

  @typedoc "SQL result field mapping"
  @type result_field :: %{
          sql_column: String.t(),
          path: list(String.t()),
          is_json: boolean()
        }

  @typedoc "SQL result structure"
  @type t :: %__MODULE__{
          fields: list(result_field()),
          # Map of path to list of prefixes
          nested_objects: map()
        }

  defstruct fields: [], nested_objects: %{}

  @doc """
  Creates a new result structure.

  ## Examples

      iex> GraSQL.ResultStructure.new()
      %GraSQL.ResultStructure{fields: [], nested_objects: %{}}
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Creates a result structure with the given fields and nested objects.

  ## Parameters

  - `fields`: List of result field mappings
  - `nested_objects`: Map of path to list of prefixes

  ## Examples

      iex> fields = [%{sql_column: "id", path: ["id"], is_json: false}]
      iex> nested = %{}
      iex> GraSQL.ResultStructure.new(fields, nested)
      %GraSQL.ResultStructure{
        fields: [%{sql_column: "id", path: ["id"], is_json: false}],
        nested_objects: %{}
      }
  """
  @spec new(list(result_field()), map()) :: t()
  def new(fields, nested_objects) when is_list(fields) and is_map(nested_objects) do
    %__MODULE__{
      fields: fields,
      nested_objects: nested_objects
    }
  end

  @doc """
  Adds a field mapping to the result structure.

  ## Parameters

  - `structure`: The result structure
  - `sql_column`: The SQL column name
  - `path`: The path in the GraphQL response
  - `is_json`: Whether the field contains JSON data

  ## Examples

      iex> structure = GraSQL.ResultStructure.new()
      iex> GraSQL.ResultStructure.add_field(structure, "u_id", ["user", "id"], false)
      %GraSQL.ResultStructure{
        fields: [%{sql_column: "u_id", path: ["user", "id"], is_json: false}],
        nested_objects: %{}
      }
  """
  @spec add_field(t(), String.t(), list(String.t()), boolean()) :: t()
  def add_field(%__MODULE__{fields: fields} = structure, sql_column, path, is_json) do
    field = %{
      sql_column: sql_column,
      path: path,
      is_json: is_json
    }

    %{structure | fields: [field | fields]}
  end

  @doc """
  Adds a nested object mapping to the result structure.

  ## Parameters

  - `structure`: The result structure
  - `path`: The path of the nested object
  - `prefix`: The SQL column prefix for this object

  ## Examples

      iex> structure = GraSQL.ResultStructure.new()
      iex> GraSQL.ResultStructure.add_nested_object(structure, ["user"], "u_")
      %GraSQL.ResultStructure{
        fields: [],
        nested_objects: %{["user"] => ["u_"]}
      }

      iex> structure = %GraSQL.ResultStructure{
      ...>   nested_objects: %{["user"] => ["u_"]}
      ...> }
      iex> GraSQL.ResultStructure.add_nested_object(structure, ["user"], "user_")
      %GraSQL.ResultStructure{
        fields: [],
        nested_objects: %{["user"] => ["u_", "user_"]}
      }
  """
  @spec add_nested_object(t(), list(String.t()), String.t()) :: t()
  def add_nested_object(%__MODULE__{nested_objects: objects} = structure, path, prefix) do
    updated_prefixes =
      case Map.get(objects, path) do
        nil -> [prefix]
        existing -> existing ++ [prefix]
      end

    %{structure | nested_objects: Map.put(objects, path, updated_prefixes)}
  end

  @doc """
  Gets all field mappings for a specific path.

  ## Parameters

  - `structure`: The result structure
  - `path`: The path to get fields for

  ## Examples

      iex> fields = [
      ...>   %{sql_column: "u_id", path: ["user", "id"], is_json: false},
      ...>   %{sql_column: "u_name", path: ["user", "name"], is_json: false},
      ...>   %{sql_column: "p_id", path: ["post", "id"], is_json: false}
      ...> ]
      iex> structure = GraSQL.ResultStructure.new(fields, %{})
      iex> GraSQL.ResultStructure.get_fields_for_path(structure, ["user"])
      [
        %{sql_column: "u_id", path: ["user", "id"], is_json: false},
        %{sql_column: "u_name", path: ["user", "name"], is_json: false}
      ]
  """
  @spec get_fields_for_path(t(), list(String.t())) :: list(result_field())
  def get_fields_for_path(%__MODULE__{fields: fields}, path) do
    path_len = length(path)

    Enum.filter(fields, fn %{path: field_path} ->
      List.starts_with?(field_path, path) && length(field_path) > path_len
    end)
  end
end
