defmodule GraSQL.SchemaNeeds do
  @moduledoc """
  Represents database objects needed to fulfill a GraphQL query.

  SchemaNeeds collects and represents all entities and relationships
  required to execute a GraphQL query. This information is used during
  schema resolution before SQL generation.

  ## Memory Usage

  Schema needs entities and relationships are stored as lists to maintain order
  and provide a clear reference structure to be resolved into full database
  schema information.
  """

  @typedoc "Collection of entity and relationship references needed for a query"
  @type t :: %__MODULE__{
          entity_references: [GraSQL.EntityReference.t()],
          relationship_references: [GraSQL.RelationshipReference.t()]
        }

  defstruct entity_references: [],
            relationship_references: []

  @doc """
  Creates a new schema needs collection.

  ## Examples

      iex> GraSQL.SchemaNeeds.new()
      %GraSQL.SchemaNeeds{entity_references: [], relationship_references: []}
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Creates a schema needs collection with the given entity and relationship references.

  ## Parameters

  - `entity_references`: List of entity references
  - `relationship_references`: List of relationship references

  ## Examples

      iex> entity_refs = [%GraSQL.EntityReference{graphql_name: "users"}]
      iex> relationship_refs = []
      iex> schema_needs = GraSQL.SchemaNeeds.new(entity_refs, relationship_refs)
      iex> length(schema_needs.entity_references)
      1
  """
  @spec new(list(GraSQL.EntityReference.t()), list(GraSQL.RelationshipReference.t())) :: t()
  def new(entity_references, relationship_references)
      when is_list(entity_references) and is_list(relationship_references) do
    %__MODULE__{
      entity_references: entity_references,
      relationship_references: relationship_references
    }
  end

  @doc """
  Adds an entity reference to the schema needs.

  ## Parameters

  - `schema_needs`: The schema needs collection
  - `entity_ref`: The entity reference to add

  ## Examples

      iex> needs = GraSQL.SchemaNeeds.new()
      iex> entity = %GraSQL.EntityReference{graphql_name: "users"}
      iex> updated = GraSQL.SchemaNeeds.add_entity(needs, entity)
      iex> length(updated.entity_references)
      1
  """
  @spec add_entity(t(), GraSQL.EntityReference.t()) :: t()
  def add_entity(%__MODULE__{entity_references: entity_references} = schema_needs, entity_ref) do
    existing_entity =
      Enum.find(entity_references, fn e ->
        e.graphql_name == entity_ref.graphql_name
      end)

    if existing_entity do
      schema_needs
    else
      %{schema_needs | entity_references: [entity_ref | entity_references]}
    end
  end

  @doc """
  Adds a relationship reference to the schema needs.

  ## Parameters

  - `schema_needs`: The schema needs collection
  - `rel_ref`: The relationship reference to add

  ## Examples

      iex> needs = GraSQL.SchemaNeeds.new()
      iex> rel = %GraSQL.RelationshipReference{parent_name: "users", child_name: "posts"}
      iex> updated = GraSQL.SchemaNeeds.add_relationship(needs, rel)
      iex> length(updated.relationship_references)
      1
  """
  @spec add_relationship(t(), GraSQL.RelationshipReference.t()) :: t()
  def add_relationship(
        %__MODULE__{relationship_references: relationship_references} = schema_needs,
        rel_ref
      ) do
    existing_rel =
      Enum.find(relationship_references, fn r ->
        r.parent_name == rel_ref.parent_name &&
          r.child_name == rel_ref.child_name &&
          r.parent_alias == rel_ref.parent_alias &&
          r.child_alias == rel_ref.child_alias
      end)

    if existing_rel do
      schema_needs
    else
      %{schema_needs | relationship_references: [rel_ref | relationship_references]}
    end
  end

  @doc """
  Merges two SchemaNeeds structs into a single combined struct.

  ## Examples

      iex> entity_ref = %GraSQL.EntityReference{graphql_name: "users"}
      iex> rel_ref = %GraSQL.RelationshipReference{parent_name: "users", child_name: "posts"}
      iex> needs1 = %GraSQL.SchemaNeeds{entity_references: [entity_ref], relationship_references: []}
      iex> needs2 = %GraSQL.SchemaNeeds{entity_references: [], relationship_references: [rel_ref]}
      iex> result = GraSQL.SchemaNeeds.merge_schema_needs(needs1, needs2)
      iex> length(result.entity_references)
      1
      iex> length(result.relationship_references)
      1
  """
  @spec merge_schema_needs(t(), t()) :: t()
  def merge_schema_needs(%__MODULE__{} = needs1, %__MODULE__{} = needs2) do
    # Combine entity references, avoiding duplicates
    combined_entities =
      (needs1.entity_references ++ needs2.entity_references)
      |> Enum.uniq_by(fn entity -> entity.graphql_name end)

    # Combine relationship references, avoiding duplicates
    combined_relationships =
      (needs1.relationship_references ++ needs2.relationship_references)
      |> Enum.uniq_by(fn rel -> {rel.parent_name, rel.child_name} end)

    %__MODULE__{
      entity_references: combined_entities,
      relationship_references: combined_relationships
    }
  end
end

defmodule GraSQL.EntityReference do
  @moduledoc """
  Represents a reference to an entity from a GraphQL query.

  EntityReference identifies a GraphQL field that represents an entity
  and is used to track which entities are needed to fulfill a query,
  without making assumptions about database structure.
  """

  @typedoc "Reference to an entity in a GraphQL query"
  @type t :: %__MODULE__{
          graphql_name: String.t(),
          alias: String.t() | nil
        }

  defstruct [:graphql_name, :alias]
end

defmodule GraSQL.RelationshipReference do
  @moduledoc """
  Represents a reference to a relationship between entities from a GraphQL query.

  RelationshipReference describes how GraphQL fields are related in a query,
  without making assumptions about database structure.
  """

  @typedoc "Reference to a relationship in a GraphQL query"
  @type t :: %__MODULE__{
          parent_name: String.t(),
          child_name: String.t(),
          parent_alias: String.t() | nil,
          child_alias: String.t() | nil
        }

  defstruct [:parent_name, :child_name, :parent_alias, :child_alias]
end
