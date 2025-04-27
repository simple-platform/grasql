defmodule GraSQL.SchemaNeeds do
  @moduledoc """
  Represents database objects needed to fulfill a GraphQL query.

  SchemaNeeds collects and represents all tables and relationships
  required to execute a GraphQL query. This information is used during
  SQL generation to create proper FROM and JOIN clauses.

  ## Memory Usage

  Schema needs use MapSet for efficient membership checks and to eliminate
  duplicates automatically. This provides O(1) lookups without the memory
  overhead of maintaining separate collections.

  ## Cross-Schema Determination

  Cross-schema needs are inferred based on table references in Phase 2.
  This module provides the foundation for collecting those references.
  """

  @typedoc "Collection of database objects needed for a query"
  @type t :: %__MODULE__{
          tables: MapSet.t(GraSQL.TableRef.t()),
          relationships: MapSet.t(GraSQL.RelationshipRef.t())
        }

  defstruct tables: MapSet.new(), relationships: MapSet.new()

  @doc """
  Creates a new schema needs collection.

  ## Examples

      iex> GraSQL.SchemaNeeds.new()
      %GraSQL.SchemaNeeds{tables: MapSet.new(), relationships: MapSet.new()}
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Creates a schema needs collection with the given tables and relationships.

  ## Parameters

  - `tables`: List of table references
  - `relationships`: List of relationship references

  ## Examples

      iex> tables = [GraSQL.TableRef.new("public", "users", nil)]
      iex> relationships = []
      iex> schema_needs = GraSQL.SchemaNeeds.new(tables, relationships)
      iex> MapSet.size(schema_needs.tables)
      1
  """
  @spec new(list(GraSQL.TableRef.t()), list(GraSQL.RelationshipRef.t())) :: t()
  def new(tables, relationships) when is_list(tables) and is_list(relationships) do
    %__MODULE__{
      tables: MapSet.new(tables),
      relationships: MapSet.new(relationships)
    }
  end

  @doc """
  Adds a table reference to the schema needs.

  Uses O(1) lookup to check if the table already exists.

  ## Parameters

  - `schema_needs`: The schema needs collection
  - `table_ref`: The table reference to add

  ## Examples

      iex> needs = GraSQL.SchemaNeeds.new()
      iex> table = GraSQL.TableRef.new("public", "users", nil)
      iex> updated = GraSQL.SchemaNeeds.add_table(needs, table)
      iex> MapSet.size(updated.tables)
      1
  """
  @spec add_table(t(), GraSQL.TableRef.t()) :: t()
  def add_table(%__MODULE__{tables: tables} = schema_needs, table_ref) do
    existing_table =
      Enum.find(MapSet.to_list(tables), fn t ->
        GraSQL.TableRef.same_table?(t, table_ref)
      end)

    if existing_table do
      schema_needs
    else
      %{schema_needs | tables: MapSet.put(tables, table_ref)}
    end
  end

  @doc """
  Adds a relationship reference to the schema needs.

  Uses O(1) lookup with hash-based identity check.

  ## Parameters

  - `schema_needs`: The schema needs collection
  - `rel_ref`: The relationship reference to add

  ## Examples

      iex> needs = GraSQL.SchemaNeeds.new()
      iex> source = GraSQL.TableRef.new("public", "users", nil)
      iex> target = GraSQL.TableRef.new("public", "posts", nil)
      iex> rel = GraSQL.RelationshipRef.has_many(source, target, "id", "user_id")
      iex> updated = GraSQL.SchemaNeeds.add_relationship(needs, rel)
      iex> MapSet.size(updated.relationships)
      1
  """
  @spec add_relationship(t(), GraSQL.RelationshipRef.t()) :: t()
  def add_relationship(%__MODULE__{relationships: relationships} = schema_needs, rel_ref) do
    existing_rel =
      Enum.find(MapSet.to_list(relationships), fn r ->
        GraSQL.RelationshipRef.same_relationship?(r, rel_ref)
      end)

    if existing_rel do
      schema_needs
    else
      %{schema_needs | relationships: MapSet.put(relationships, rel_ref)}
    end
  end
end
