defmodule GraSQL.SchemaNeeds do
  @moduledoc """
  Represents database objects needed to fulfill a GraphQL query.

  SchemaNeeds collects and represents all tables and relationships
  required to execute a GraphQL query. This information is used during
  SQL generation to create proper FROM and JOIN clauses.

  ## Memory Usage

  Schema needs use a hybrid approach with both lists and maps for efficient
  lookups. Tables and relationships are stored as lists, but hash-based maps
  provide O(1) membership checks to eliminate duplicates.

  ## Cross-Schema Determination

  Cross-schema needs are inferred based on table references in Phase 2.
  This module provides the foundation for collecting those references.
  """

  @typedoc "Collection of database objects needed for a query"
  @type t :: %__MODULE__{
          tables: [GraSQL.TableRef.t()],
          relationships: [GraSQL.RelationshipRef.t()],
          # Internal map for O(1) table existence check
          table_map: map(),
          # Internal map for O(1) relationship existence check
          relationship_map: map()
        }

  defstruct tables: [], relationships: [], table_map: %{}, relationship_map: %{}

  @doc """
  Creates a new schema needs collection.

  ## Examples

      iex> GraSQL.SchemaNeeds.new()
      %GraSQL.SchemaNeeds{tables: [], relationships: [], table_map: %{}, relationship_map: %{}}
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
      iex> length(schema_needs.tables)
      1
  """
  @spec new(list(GraSQL.TableRef.t()), list(GraSQL.RelationshipRef.t())) :: t()
  def new(tables, relationships) when is_list(tables) and is_list(relationships) do
    # Build table map for O(1) lookups
    table_map =
      tables
      |> Enum.map(fn table -> {GraSQL.TableRef.hash(table), true} end)
      |> Enum.into(%{})

    # Build relationship map for O(1) lookups
    relationship_map =
      relationships
      |> Enum.map(fn rel -> {GraSQL.RelationshipRef.hash(rel), true} end)
      |> Enum.into(%{})

    %__MODULE__{
      tables: tables,
      relationships: relationships,
      table_map: table_map,
      relationship_map: relationship_map
    }
  end

  @doc """
  Adds a table reference to the schema needs.

  Uses O(1) lookup to check if the table already exists with hash-based
  identity check.

  ## Parameters

  - `schema_needs`: The schema needs collection
  - `table_ref`: The table reference to add

  ## Examples

      iex> needs = GraSQL.SchemaNeeds.new()
      iex> table = GraSQL.TableRef.new("public", "users", nil)
      iex> updated = GraSQL.SchemaNeeds.add_table(needs, table)
      iex> length(updated.tables)
      1
  """
  @spec add_table(t(), GraSQL.TableRef.t()) :: t()
  def add_table(
        %__MODULE__{tables: tables, table_map: table_map} = schema_needs,
        table_ref
      ) do
    # Hash-based O(1) existence check
    table_hash = GraSQL.TableRef.hash(table_ref)

    if Map.has_key?(table_map, table_hash) do
      schema_needs
    else
      %{
        schema_needs
        | tables: [table_ref | tables],
          table_map: Map.put(table_map, table_hash, true)
      }
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
      iex> length(updated.relationships)
      1
  """
  @spec add_relationship(t(), GraSQL.RelationshipRef.t()) :: t()
  def add_relationship(
        %__MODULE__{
          relationships: relationships,
          relationship_map: relationship_map
        } = schema_needs,
        rel_ref
      ) do
    # Hash-based O(1) existence check
    rel_hash = GraSQL.RelationshipRef.hash(rel_ref)

    if Map.has_key?(relationship_map, rel_hash) do
      schema_needs
    else
      %{
        schema_needs
        | relationships: [rel_ref | relationships],
          relationship_map: Map.put(relationship_map, rel_hash, true)
      }
    end
  end
end
