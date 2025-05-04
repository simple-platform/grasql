defmodule GraSQL.Schema do
  @moduledoc """
  Handles the resolution of GraphQL fields to database schema.

  This module translates GraphQL field paths to concrete database tables
  and relationships for SQL generation. It provides:

  * Resolution of root-level GraphQL fields to database tables
  * Resolution of nested fields to table relationships
  * Parallel processing of schema resolution for performance
  * Formatting of schema information for SQL generation

  ## Examples

      # With a properly configured resolver
      resolution_request = %{field_names: ["users", "posts"], field_paths: [["users"], ["users", "posts"]]}
      resolver = MyApp.SchemaResolver
      schema = GraSQL.Schema.resolve(resolution_request, resolver)

      # The returned schema contains tables, relationships and a path map for efficient access
      %{
        tables: [%GraSQL.Schema.Table{...}],
        relationships: [%GraSQL.Schema.Relationship{...}],
        path_map: %{...}
      }
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
    """
    @type t :: %__MODULE__{
            schema: String.t(),
            name: String.t()
          }

    defstruct [:schema, :name]
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

  # Public API
  #############################################################################

  @doc """
  Resolves GraphQL field paths to database schema.

  Translates GraphQL field names and paths to database tables and relationships
  using the provided resolver module.

  ## Parameters

  * `resolution_request` - The resolution request from the parser
  * `resolver` - The module implementing the SchemaResolver behavior
  * `context` - User-provided context information

  ## Returns

  * A map with the following keys:
    - `tables` - List of all resolved tables
    - `relationships` - List of all resolved relationships
    - `path_map` - Map of field paths to tables/relationships for efficient lookup

  ## Examples

      # Resolve a simple request with users and their posts
      resolution_request = %{
        field_names: ["users", "id", "name", "posts", "title"],
        field_paths: [
          ["users"],
          ["users", "id"],
          ["users", "name"],
          ["users", "posts"],
          ["users", "posts", "title"]
        ]
      }

      schema = GraSQL.Schema.resolve(resolution_request, MyApp.SchemaResolver)
  """
  @spec resolve(map() | tuple(), module(), map()) :: map()
  def resolve(resolution_request, resolver, context \\ %{}) do
    # Extract field names and paths
    {field_names, field_paths} = extract_resolution_info(resolution_request)

    # Process tables and relationships
    {tables, relationships} = resolve_schema(field_paths, field_names, resolver, context)

    # Format for SQL generation
    format_for_sql_generation(tables, relationships, field_paths)
  end

  # Resolution Request Processing
  #############################################################################

  @doc false
  @spec extract_resolution_info({atom(), list(), atom(), list()} | map()) :: {list(), list()}
  defp extract_resolution_info({:field_names, field_names, :field_paths, field_paths}) do
    # Convert paths of indices to paths of string names
    string_paths =
      field_paths
      |> Enum.map(fn path ->
        Enum.map(path, fn index -> Enum.at(field_names, index) end)
      end)

    {field_names, string_paths}
  end

  @doc false
  defp extract_resolution_info(resolution_request) when is_map(resolution_request) do
    field_names = Map.get(resolution_request, :field_names, [])
    field_paths = Map.get(resolution_request, :field_paths, [])
    {field_names, field_paths}
  end

  # Schema Resolution
  #############################################################################

  @doc false
  @spec resolve_schema(list(), list(), module(), map()) :: {map(), map()}
  defp resolve_schema(field_paths, _field_names, resolver, context) do
    # Get unique root tables to resolve
    root_table_names =
      field_paths
      |> Enum.map(fn path -> List.first(path) end)
      |> Enum.uniq()

    # Resolve root tables in parallel
    root_tables = resolve_root_tables(root_table_names, resolver, context)

    # Process relationships level by level
    relationship_paths_by_depth = group_relationship_paths_by_depth(field_paths)

    # Process each level of relationships
    Enum.reduce(relationship_paths_by_depth, {root_tables, %{}}, fn {_depth, paths},
                                                                    {tables, relationships} ->
      resolve_relationship_level(paths, tables, relationships, resolver, context)
    end)
  end

  @doc false
  @spec resolve_root_tables(list(), module(), map()) :: map()
  defp resolve_root_tables(root_table_names, resolver, context) do
    root_table_names
    |> Task.async_stream(
      fn field_name ->
        try do
          {field_name, resolver.resolve_table(field_name, context)}
        rescue
          e ->
            {:error, field_name, e}
        catch
          kind, value ->
            {:error, field_name, {kind, value}}
        end
      end,
      max_concurrency: System.schedulers_online()
    )
    |> Enum.map(fn
      {:ok, {:error, field_name, error}} when is_exception(error) ->
        raise "Root table resolution failed for '#{field_name}': #{Exception.message(error)}"

      {:ok, {:error, field_name, {kind, value}}} ->
        raise "Root table resolution failed for '#{field_name}': #{inspect(kind)} #{inspect(value)}"

      {:ok, result} ->
        result

      {:exit, reason} ->
        raise "Root table resolution task failed: #{inspect(reason)}"
    end)
    |> Map.new()
  end

  @doc false
  @spec group_relationship_paths_by_depth(list()) :: [{integer(), list()}]
  defp group_relationship_paths_by_depth(field_paths) do
    field_paths
    |> Enum.filter(fn path -> length(path) > 1 end)
    |> Enum.flat_map(fn path ->
      # For each path, create all parent-child pairs
      1..(length(path) - 1)
      |> Enum.map(fn i ->
        parent_field = Enum.at(path, i - 1)
        field_name = Enum.at(path, i)
        {Enum.take(path, i + 1), {parent_field, field_name}, i}
      end)
    end)
    |> Enum.group_by(fn {_path, _fields, depth} -> depth end)
    |> Enum.sort_by(fn {depth, _} -> depth end)
  end

  @doc false
  @spec resolve_relationship_level(list(), map(), map(), module(), map()) :: {map(), map()}
  defp resolve_relationship_level(paths, tables, relationships, resolver, context) do
    # Extract unique relationship tasks for this level
    relationship_tasks =
      paths
      |> Enum.uniq_by(fn {path, _, _} -> path end)
      |> Enum.map(fn {path, fields, _} -> {path, fields} end)
      |> Map.new()

    # Resolve relationships for this level in parallel
    level_relationships =
      relationship_tasks
      |> Task.async_stream(
        fn {path, {_parent_field, field_name}} ->
          try do
            # Find parent table (either root or from a previous relationship)
            parent_path = Enum.drop(path, -1)
            parent_table = find_parent_table(parent_path, tables, relationships)

            # Resolve the relationship (doing the expensive work IN the task)
            relationship = resolver.resolve_relationship(field_name, parent_table, context)
            {path, relationship}
          rescue
            e ->
              {:error, path, field_name, e}
          catch
            kind, value ->
              {:error, path, field_name, {kind, value}}
          end
        end,
        max_concurrency: System.schedulers_online()
      )
      |> Enum.map(fn
        {:ok, {:error, path, field_name, error}} when is_exception(error) ->
          raise "Relationship resolution failed for '#{field_name}' at path #{inspect(path)}: #{Exception.message(error)}"

        {:ok, {:error, path, field_name, {kind, value}}} ->
          raise "Relationship resolution failed for '#{field_name}' at path #{inspect(path)}: #{inspect(kind)} #{inspect(value)}"

        {:ok, result} ->
          result

        {:exit, reason} ->
          raise "Relationship resolution task failed: #{inspect(reason)}"
      end)
      |> Map.new()

    # Add target tables to the tables map
    updated_tables =
      Enum.reduce(level_relationships, tables, fn {_path, rel}, acc ->
        Map.put_new(acc, rel.target_table.name, rel.target_table)
      end)

    # Return updated tables and relationships for the next level
    {updated_tables, Map.merge(relationships, level_relationships)}
  end

  @doc false
  @spec find_parent_table(list(), map(), map()) :: Table.t()
  defp find_parent_table(parent_path, tables, relationships) do
    if length(parent_path) == 1 do
      # Direct child of root table
      Map.fetch!(tables, hd(parent_path))
    else
      # Child of a previously resolved relationship
      rel_path = parent_path
      rel = Map.fetch!(relationships, rel_path)
      rel.target_table
    end
  end

  # SQL Generation Formatting
  #############################################################################

  @doc false
  @spec format_for_sql_generation(map(), map(), list()) :: map()
  defp format_for_sql_generation(tables, relationships, _field_paths) do
    # Create a path map for O(1) lookups
    path_map = create_path_map(tables, relationships)

    # Return a minimalist structure for SQL generation
    %{
      tables: Map.values(tables),
      relationships: Map.values(relationships),
      path_map: path_map
    }
  end

  @doc false
  @spec create_path_map(map(), map()) :: map()
  defp create_path_map(tables, relationships) do
    # Map tables by path
    table_paths =
      tables
      |> Enum.map(fn {field_name, table} -> {[field_name], {:table, table}} end)
      |> Map.new()

    # Map relationships by path
    relationship_paths =
      relationships
      |> Enum.map(fn {path, relationship} -> {path, {:relationship, relationship}} end)
      |> Map.new()

    # Combine maps
    Map.merge(table_paths, relationship_paths)
  end
end
