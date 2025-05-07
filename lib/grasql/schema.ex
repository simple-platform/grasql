defmodule GraSQL.Schema do
  @moduledoc """
  Defines the schema structure and resolution logic for GraSQL.

  This module provides the core schema functionality for mapping GraphQL
  queries to database structures, including:

  - Table definitions and relationships
  - Column information and attributes
  - Schema resolution and validation

  The module defines several struct types used throughout the resolution process
  that represent database tables, relationships, columns, and join tables.
  """

  # Schema Structure Definitions
  #############################################################################

  defmodule Table do
    @moduledoc """
    Represents a resolved database table.

    Contains the schema and name information needed to construct
    valid SQL queries for a particular table.
    """

    @typedoc """
    Table schema information.

    ## Fields

    * `schema` - Database schema name (e.g., "public")
    * `name` - Table name in the database
    * `__typename` - Optional GraphQL __typename value for the table
    """
    @type t :: %__MODULE__{
            schema: String.t(),
            name: String.t(),
            __typename: String.t() | nil
          }

    defstruct [:schema, :name, :__typename]
  end

  defmodule JoinTable do
    @moduledoc """
    Represents a join table in a many-to-many relationship.

    Contains information about the intermediate table used to connect
    two entities in a many-to-many relationship, including the columns
    used for joining.
    """

    @typedoc """
    Join table schema information.

    ## Fields

    * `schema` - Database schema name
    * `name` - Join table name
    * `source_columns` - Columns in the join table that reference the source table
    * `target_columns` - Columns in the join table that reference the target table
    """
    @type t :: %__MODULE__{
            schema: String.t(),
            name: String.t(),
            source_columns: list(String.t()),
            target_columns: list(String.t())
          }

    defstruct [:schema, :name, :source_columns, :target_columns]
  end

  defmodule Relationship do
    @moduledoc """
    Represents a resolved database relationship.

    Contains complete information about how two tables are related,
    including the relationship type and joining columns.
    """

    @typedoc """
    Supported relationship types.

    * `:belongs_to` - Child entity belongs to parent (foreign key on child)
    * `:has_one` - Parent has exactly one child (foreign key on child)
    * `:has_many` - Parent has multiple children (foreign key on children)
    * `:many_to_many` - Many-to-many relationship through a join table
    """
    @type relationship_type :: :belongs_to | :has_one | :has_many | :many_to_many

    @typedoc """
    Relationship schema information.

    ## Fields

    * `source_table` - The parent/source table in the relationship
    * `target_table` - The child/target table in the relationship
    * `join_table` - Optional join table for many-to-many relationships
    * `source_columns` - Columns in the source table used for joining
    * `target_columns` - Columns in the target table used for joining
    * `type` - The type of relationship
    """
    @type t :: %__MODULE__{
            source_table: GraSQL.Schema.Table.t(),
            target_table: GraSQL.Schema.Table.t(),
            join_table: GraSQL.Schema.JoinTable.t() | nil,
            source_columns: list(String.t()),
            target_columns: list(String.t()),
            type: relationship_type()
          }

    defstruct [:source_table, :target_table, :join_table, :source_columns, :target_columns, :type]
  end

  defmodule Column do
    @moduledoc """
    Represents a database column with its attributes.

    Contains the SQL type and default value information needed for
    generating appropriate SQL queries.
    """

    @typedoc """
    Column schema information.

    ## Fields
    * `name` - Column name in the database
    * `sql_type` - SQL data type of the column
    * `default_value` - Default value for the column (if any)
    * `is_required` - Whether the column is required
    """
    @type t :: %__MODULE__{
            name: String.t(),
            sql_type: String.t(),
            default_value: any(),
            is_required: boolean()
          }

    defstruct [:name, :sql_type, :default_value, :is_required]
  end

  @doc """
  Resolves a GraphQL schema against a database schema.

  This function processes a GraphQL query resolution request by
  calling the schema resolver to map GraphQL entities to database tables
  and relationships.

  ## Parameters

  * `resolution_request` - The parsed GraphQL query with field paths
  * `context` - Optional context for schema resolution

  ## Returns

  A resolution response that can be passed to SQL generation
  """
  @spec resolve(map(), map()) :: map()
  def resolve(resolution_request, context \\ %{}) do
    # Use provided resolver or get from cache
    resolver = get_cached_resolver()

    # Process resolution request with resolver
    process_resolution(resolution_request, resolver, context)
  end

  # Get the resolver from cache
  @spec get_cached_resolver() :: module()
  defp get_cached_resolver do
    case GraSQL.SchemaResolverCache.get_resolver() do
      {:ok, resolver} -> resolver
      {:error, reason} -> raise "Failed to get schema resolver: #{reason}"
    end
  end

  # Process the resolution request (placeholder for Phase 2 implementation)
  @spec process_resolution(map(), module(), map()) :: map()
  defp process_resolution(resolution_request, _resolver, _context) do
    # Process the resolution request by calling the schema resolver
    # This is a simple implementation that forwards the request directly
    # In a more complex implementation, this could perform additional processing
    resolution_request
  end
end
