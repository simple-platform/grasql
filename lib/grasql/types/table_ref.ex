defmodule GraSQL.TableRef do
  @moduledoc """
  Represents a reference to a database table.

  TableRef is used to identify and describe tables needed to fulfill a GraphQL
  query. This information is collected during query analysis and used during
  SQL generation.

  ## Memory Usage

  Table references are designed to be lightweight, with string schema and table
  names potentially benefiting from interning in large queries.
  """

  @typedoc "Reference to a database table"
  @type t :: %__MODULE__{
          schema: String.t(),
          table: String.t(),
          alias: String.t() | nil
        }

  defstruct [:schema, :table, :alias]

  @doc """
  Creates a new table reference.

  ## Parameters

  - `schema`: The database schema name
  - `table`: The table name
  - `alias`: Optional alias for the table in SQL queries

  ## Examples

      iex> GraSQL.TableRef.new("public", "users", nil)
      %GraSQL.TableRef{schema: "public", table: "users", alias: nil}

      iex> GraSQL.TableRef.new("auth", "users", "u")
      %GraSQL.TableRef{schema: "auth", table: "users", alias: "u"}
  """
  @spec new(String.t(), String.t(), String.t() | nil) :: t()
  def new(schema, table, alias) do
    %__MODULE__{
      schema: schema,
      table: table,
      alias: alias
    }
  end

  @doc """
  Returns the fully qualified table name with schema.

  ## Parameters

  - `table_ref`: The table reference

  ## Examples

      iex> table_ref = GraSQL.TableRef.new("public", "users", nil)
      iex> GraSQL.TableRef.full_table_name(table_ref)
      "public.users"
  """
  @spec full_table_name(t()) :: String.t()
  def full_table_name(%__MODULE__{schema: schema, table: table}) do
    "#{schema}.#{table}"
  end

  @doc """
  Returns the effective name of the table in SQL queries, using the alias if present.

  ## Parameters

  - `table_ref`: The table reference

  ## Examples

      iex> table_ref = GraSQL.TableRef.new("public", "users", "u")
      iex> GraSQL.TableRef.effective_name(table_ref)
      "u"

      iex> table_ref = GraSQL.TableRef.new("public", "users", nil)
      iex> GraSQL.TableRef.effective_name(table_ref)
      "users"
  """
  @spec effective_name(t()) :: String.t()
  def effective_name(%__MODULE__{table: table, alias: nil}), do: table
  def effective_name(%__MODULE__{alias: alias}) when not is_nil(alias), do: alias

  @doc """
  Determines if two table references refer to the same table (ignoring alias).

  ## Parameters

  - `table_ref1`: First table reference
  - `table_ref2`: Second table reference

  ## Examples

      iex> t1 = GraSQL.TableRef.new("public", "users", nil)
      iex> t2 = GraSQL.TableRef.new("public", "users", "u")
      iex> GraSQL.TableRef.same_table?(t1, t2)
      true

      iex> t1 = GraSQL.TableRef.new("public", "users", nil)
      iex> t2 = GraSQL.TableRef.new("public", "posts", nil)
      iex> GraSQL.TableRef.same_table?(t1, t2)
      false
  """
  @spec same_table?(t(), t()) :: boolean()
  def same_table?(%__MODULE__{schema: s1, table: t1}, %__MODULE__{schema: s2, table: t2}) do
    s1 == s2 && t1 == t2
  end

  @doc """
  Generates a hash value for the table reference (ignoring alias).
  Used for efficient comparison in collections.

  ## Parameters

  - `table_ref`: The table reference

  ## Examples

      iex> t1 = GraSQL.TableRef.new("public", "users", nil)
      iex> t2 = GraSQL.TableRef.new("public", "users", "u")
      iex> GraSQL.TableRef.hash(t1) == GraSQL.TableRef.hash(t2)
      true
  """
  @spec hash(t()) :: integer()
  def hash(%__MODULE__{schema: schema, table: table}) do
    :erlang.phash2({schema, table})
  end
end
