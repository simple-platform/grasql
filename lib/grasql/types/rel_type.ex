defmodule GraSQL.RelType do
  @moduledoc """
  Defines relationship types between database tables.

  This module provides constants for different types of relationships
  that can exist between tables in a database schema. These relationship
  types are used to describe how data should be joined and structured
  when generating SQL.

  ## Memory Usage

  Relationship types are represented as atoms, providing zero memory overhead
  for repeated references to the same relationship type.
  """

  @typedoc "Relationship type represented as an atom"
  @type t :: :belongs_to | :has_one | :has_many

  @doc """
  Returns the belongs_to relationship type.

  A belongs_to relationship means multiple rows in the first table can
  correspond to the same row in the related table, but each row in the
  first table corresponds to exactly one row in the related table.
  (Equivalent to many-to-one)

  ## Examples

      iex> GraSQL.RelType.belongs_to()
      :belongs_to
  """
  @spec belongs_to() :: :belongs_to
  def belongs_to, do: :belongs_to

  @doc """
  Returns the has_one relationship type.

  A has_one relationship means each row in the first table corresponds
  to exactly one row in the related table, and vice versa.
  (Equivalent to one-to-one)

  ## Examples

      iex> GraSQL.RelType.has_one()
      :has_one
  """
  @spec has_one() :: :has_one
  def has_one, do: :has_one

  @doc """
  Returns the has_many relationship type.

  A has_many relationship means each row in the first table can have
  multiple corresponding rows in the related table, but each row in the
  related table corresponds to exactly one row in the first table.
  (Equivalent to one-to-many)

  Many-to-many relationships are represented as has_many with a via_table
  property in the RelationshipRef.

  ## Examples

      iex> GraSQL.RelType.has_many()
      :has_many
  """
  @spec has_many() :: :has_many
  def has_many, do: :has_many
end
