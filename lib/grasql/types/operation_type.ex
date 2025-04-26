defmodule GraSQL.OperationType do
  @moduledoc """
  Defines the types of GraphQL operations supported by GraSQL.

  This module provides constants and helper functions for working with
  GraphQL operation types, currently supporting:
  - Query operations (read-only)
  - Mutation operations (data modification)

  ## Memory Usage

  Operation types are represented as atoms, providing zero memory overhead
  for repeated references to the same operation type.
  """

  @typedoc "Operation type represented as an atom"
  @type t :: :query | :mutation

  @doc """
  Returns the query operation type.

  ## Examples

      iex> GraSQL.OperationType.query()
      :query
  """
  @spec query() :: :query
  def query, do: :query

  @doc """
  Returns the mutation operation type.

  ## Examples

      iex> GraSQL.OperationType.mutation()
      :mutation
  """
  @spec mutation() :: :mutation
  def mutation, do: :mutation
end
