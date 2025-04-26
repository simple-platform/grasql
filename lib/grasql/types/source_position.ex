defmodule GraSQL.SourcePosition do
  @moduledoc """
  Represents a position in a GraphQL source document.

  This struct is used for error reporting and debugging, allowing precise
  identification of where in the original GraphQL query a particular
  field or fragment is defined.

  ## Memory Usage

  SourcePosition uses two integers, making it a lightweight structure
  even when many instances are needed for a complex query.
  """

  @typedoc "Source position with line and column information"
  @type t :: %__MODULE__{
          line: integer(),
          column: integer()
        }

  defstruct [:line, :column]

  @doc """
  Creates a new source position.

  ## Parameters

  - `line`: Line number (1-indexed)
  - `column`: Column number (1-indexed)

  ## Examples

      iex> GraSQL.SourcePosition.new(10, 5)
      %GraSQL.SourcePosition{line: 10, column: 5}
  """
  @spec new(integer(), integer()) :: t()
  def new(line, column) when is_integer(line) and is_integer(column) do
    %__MODULE__{line: line, column: column}
  end

  @doc """
  Compares two source positions to determine which comes first in the document.

  Returns:
  - `:lt` if the first position is before the second
  - `:eq` if the positions are equal
  - `:gt` if the first position is after the second

  ## Examples

      iex> pos1 = GraSQL.SourcePosition.new(10, 5)
      iex> pos2 = GraSQL.SourcePosition.new(10, 20)
      iex> GraSQL.SourcePosition.compare(pos1, pos2)
      :lt
  """
  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare(%__MODULE__{line: l1, column: c1}, %__MODULE__{line: l2, column: c2}) do
    cond do
      l1 < l2 -> :lt
      l1 > l2 -> :gt
      c1 < c2 -> :lt
      c1 > c2 -> :gt
      true -> :eq
    end
  end
end
