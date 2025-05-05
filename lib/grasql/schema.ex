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

      # The returned schema maps field paths to tables (with columns) and relationships
      %{
        ["users"] => {:table, %{
          table: %GraSQL.Schema.Table{schema: "public", name: "users", __typename: "User"},
          columns: [
            %GraSQL.Schema.Column{name: "id", sql_type: "INTEGER", default_value: nil},
            %GraSQL.Schema.Column{name: "name", sql_type: "VARCHAR(100)", default_value: nil}
          ]
        }},
        ["users", "posts"] => {:relationship, %GraSQL.Schema.Relationship{...}}
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
    """
    @type t :: %__MODULE__{
            name: String.t(),
            sql_type: String.t(),
            default_value: any()
          }

    defstruct [:name, :sql_type, :default_value]
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

  * A map of field paths to their resolved schema elements:
    - Tables with their associated columns: `{:table, %{table: table, columns: [column, ...]}}`
    - Relationships: `{:relationship, relationship}`

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
    # Extract field names, paths, column map, and operation kind
    {field_names, field_paths, column_map, operation_kind} =
      extract_resolution_info(resolution_request)

    # Process tables and relationships
    {tables, relationships} = resolve_schema(field_paths, field_names, resolver, context)

    # Determine which attributes need to be resolved based on operation type
    attributes_to_resolve = attributes_for_operation(operation_kind)

    # Process columns with parallel attribute resolution
    columns = resolve_columns(tables, column_map, attributes_to_resolve, resolver, context)

    # Format for SQL generation - operation_kind is already known by the NIF
    format_for_sql_generation(tables, relationships, columns)
  end

  # Resolution Request Processing
  #############################################################################

  @doc false
  @spec extract_resolution_info(
          {atom(), list(), atom(), list(), atom(), list(), atom(), atom()}
          | {atom(), list(), atom(), list()}
          | map()
        ) :: {list(), list(), map(), atom()}
  defp extract_resolution_info(
         {:field_names, field_names, :field_paths, field_paths, :column_map, column_map,
          :operation_kind, operation_kind}
       ) do
    # Convert paths of indices to paths of string names
    string_paths =
      field_paths
      |> Enum.map(fn path ->
        Enum.map(path, fn index -> Enum.at(field_names, index) end)
      end)

    # Convert column_map from {table_idx, [column_names]} to {table_name, [column_names]}
    table_columns =
      column_map
      |> Enum.reduce(%{}, fn {table_idx, column_names}, acc ->
        table_name = Enum.at(field_names, table_idx)
        Map.put(acc, table_name, column_names)
      end)

    {field_names, string_paths, table_columns, operation_kind}
  end

  # Add fallback for backward compatibility
  @doc false
  defp extract_resolution_info({:field_names, field_names, :field_paths, field_paths}) do
    # Existing implementation for older format
    string_paths =
      field_paths
      |> Enum.map(fn path ->
        Enum.map(path, fn index -> Enum.at(field_names, index) end)
      end)

    # Default empty column map and query operation
    {field_names, string_paths, %{}, :query}
  end

  @doc false
  defp extract_resolution_info(resolution_request) when is_map(resolution_request) do
    field_names = Map.get(resolution_request, :field_names, [])
    field_paths = Map.get(resolution_request, :field_paths, [])
    # Default empty column map and query operation
    {field_names, field_paths, %{}, :query}
  end

  @doc false
  @spec attributes_for_operation(atom()) :: list(atom())
  defp attributes_for_operation(operation_kind) do
    case operation_kind do
      :insert_mutation -> [:sql_type, :default_value]
      :update_mutation -> [:sql_type, :default_value]
      # For queries and deletes, we only need SQL type
      _ -> [:sql_type]
    end
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
  @spec resolve_columns(map(), map(), list(atom()), module(), map()) :: map()
  defp resolve_columns(tables, column_map, attributes_to_resolve, resolver, context) do
    # Process tables in parallel
    tables
    |> Task.async_stream(
      fn {table_name, table} ->
        process_table_columns(
          table_name,
          table,
          column_map,
          attributes_to_resolve,
          resolver,
          context
        )
      end,
      max_concurrency: System.schedulers_online()
    )
    |> Enum.map(fn {:ok, result} -> result end)
    |> Map.new()
  end

  @doc false
  @spec process_table_columns(
          String.t(),
          GraSQL.Schema.Table.t(),
          map(),
          list(atom()),
          module(),
          map()
        ) :: {String.t(), list()}
  defp process_table_columns(
         table_name,
         table,
         column_map,
         attributes_to_resolve,
         resolver,
         context
       ) do
    # Only resolve if table has columns to resolve
    case Map.get(column_map, table_name) do
      nil ->
        {table_name, []}

      requested_columns ->
        # Get all available columns for this table
        all_columns = resolver.resolve_columns(table, context)

        # Get relevant columns (intersection of requested and all available)
        columns_to_resolve =
          requested_columns
          |> Enum.filter(fn column -> column in all_columns end)

        # Determine if we should use parallel resolution
        column_details =
          if length(columns_to_resolve) > 10 do
            # Use parallel resolution for many columns
            resolve_columns_parallel(
              columns_to_resolve,
              table,
              attributes_to_resolve,
              resolver,
              context
            )
          else
            # Use sequential resolution for few columns
            resolve_columns_sequential(
              columns_to_resolve,
              table,
              attributes_to_resolve,
              resolver,
              context
            )
          end

        {table_name, column_details}
    end
  end

  @doc false
  @spec resolve_columns_parallel(
          list(String.t()),
          GraSQL.Schema.Table.t(),
          list(atom()),
          module(),
          map()
        ) :: list(GraSQL.Schema.Column.t())
  defp resolve_columns_parallel(columns, table, attributes_to_resolve, resolver, context) do
    columns
    |> Task.async_stream(
      fn column_name ->
        resolve_column_with_attributes(
          column_name,
          table,
          attributes_to_resolve,
          resolver,
          context
        )
      end,
      max_concurrency: System.schedulers_online()
    )
    |> Enum.map(fn {:ok, column} -> column end)
  end

  @doc false
  @spec resolve_columns_sequential(
          list(String.t()),
          GraSQL.Schema.Table.t(),
          list(atom()),
          module(),
          map()
        ) :: list(GraSQL.Schema.Column.t())
  defp resolve_columns_sequential(columns, table, attributes_to_resolve, resolver, context) do
    Enum.map(columns, fn column_name ->
      resolve_column_with_attributes(column_name, table, attributes_to_resolve, resolver, context)
    end)
  end

  @doc false
  @spec resolve_column_with_attributes(
          String.t(),
          GraSQL.Schema.Table.t(),
          list(atom()),
          module(),
          map()
        ) :: GraSQL.Schema.Column.t()
  defp resolve_column_with_attributes(
         column_name,
         table,
         attributes_to_resolve,
         resolver,
         context
       ) do
    # For each attribute, make a separate resolver call
    attributes =
      attributes_to_resolve
      |> Enum.map(fn attribute ->
        {attribute, resolver.resolve_column_attribute(attribute, column_name, table, context)}
      end)
      |> Map.new()

    # Construct column struct with resolved attributes
    %GraSQL.Schema.Column{
      name: column_name,
      sql_type: attributes[:sql_type],
      default_value: attributes[:default_value]
    }
  end

  @doc false
  @spec resolve_root_tables(list(), module(), map()) :: map()
  defp resolve_root_tables(root_table_names, resolver, context) do
    root_table_names
    |> Task.async_stream(
      fn field_name ->
        try do
          table = resolver.resolve_table(field_name, context)

          # Set typename if resolver implements the resolve_typename callback
          table_with_typename =
            if function_exported?(resolver, :resolve_typename, 2) do
              typename = resolver.resolve_typename(table, context)
              %{table | __typename: typename}
            else
              table
            end

          {field_name, table_with_typename}
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

            # Set typename on the target table if resolver implements resolve_typename
            relationship_with_typename =
              if function_exported?(resolver, :resolve_typename, 2) and relationship.target_table do
                typename = resolver.resolve_typename(relationship.target_table, context)
                target_with_typename = %{relationship.target_table | __typename: typename}
                %{relationship | target_table: target_with_typename}
              else
                relationship
              end

            {path, relationship_with_typename}
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
  @spec format_for_sql_generation(map(), map(), map()) :: map()
  defp format_for_sql_generation(tables, relationships, columns) do
    # Create a resolved schema for efficient lookups with columns embedded
    create_resolved_schema(tables, relationships, columns)
  end

  @doc false
  @spec create_resolved_schema(map(), map(), map()) :: map()
  defp create_resolved_schema(tables, relationships, columns) do
    # Map tables by path, including their columns as children
    table_paths =
      tables
      |> Enum.map(fn {field_name, table} ->
        table_columns = Map.get(columns, field_name, [])
        {[field_name], {:table, %{table: table, columns: table_columns}}}
      end)
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
