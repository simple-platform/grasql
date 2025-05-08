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
  @spec resolve(tuple(), map()) :: map()
  def resolve(resolution_request, context \\ %{}) do
    # Get resolver from application config
    resolver = get_cached_resolver()

    # Extract resolution information
    {query_id, strings, paths, path_dir, path_types, column_map, operations} =
      extract_resolution_info(resolution_request)

    # Process paths to extract tables and relationships that need resolution
    tables_to_resolve = extract_tables_to_resolve(strings, paths, path_dir, path_types)
    relations_to_resolve = extract_relationships_to_resolve(strings, paths, path_dir, path_types)

    # Determine optimal concurrency based on available schedulers and workload
    concurrency =
      min(
        System.schedulers_online(),
        max(1, length(tables_to_resolve) + length(relations_to_resolve))
      )

    # Resolve tables in parallel with optimal concurrency
    resolved_tables =
      tables_to_resolve
      |> Task.async_stream(
        fn {path_id, table_name} ->
          table = resolver.resolve_table(table_name, context)

          # Resolve __typename if callback is implemented
          table =
            if function_exported?(resolver, :resolve_typename, 2) do
              %{table | __typename: resolver.resolve_typename(table, context)}
            else
              table
            end

          {path_id, table}
        end,
        max_concurrency: concurrency,
        # Allow processing in any order for better performance
        ordered: false
      )
      |> Stream.map(fn {:ok, result} -> result end)
      |> Enum.into(%{})

    # Resolve relationships in parallel with optimal concurrency
    resolved_relationships =
      relations_to_resolve
      |> Task.async_stream(
        fn {path_id, {parent_path_id, field_name}} ->
          # Only try to resolve relationships for tables we've resolved
          case Map.fetch(resolved_tables, parent_path_id) do
            {:ok, parent_table} ->
              relationship = resolver.resolve_relationship(field_name, parent_table, context)
              {path_id, relationship}

            :error ->
              # Skip relationships we can't resolve (parent table not found)
              {path_id, nil}
          end
        end,
        max_concurrency: concurrency,
        # Allow processing in any order for better performance
        ordered: false
      )
      |> Stream.map(fn {:ok, result} -> result end)
      # Filter out skipped relationships
      |> Enum.filter(fn {_, rel} -> rel != nil end)
      |> Enum.into(%{})

    # Resolve columns for each table
    resolved_columns =
      resolve_columns(
        resolved_tables,
        column_map,
        strings,
        resolver,
        context
      )

    # Build compacted resolution response for Phase 3
    build_resolution_response(
      query_id,
      resolved_tables,
      resolved_relationships,
      resolved_columns,
      operations,
      strings
    )
  end

  # Extract resolution information from the request
  @spec extract_resolution_info(tuple()) ::
          {String.t(), list(String.t()), list(integer()), list(integer()), list(integer()),
           list(tuple()), list(tuple())}
  defp extract_resolution_info(resolution_request) do
    # Pattern match the resolution request tuple to extract all required information
    {
      :query_id,
      query_id,
      :strings,
      strings,
      :paths,
      paths,
      :path_dir,
      path_dir,
      :path_types,
      path_types,
      :cols,
      column_map,
      :ops,
      operations
    } = resolution_request

    {query_id, strings, paths, path_dir, path_types, column_map, operations}
  end

  # Extract tables that need resolution
  @spec extract_tables_to_resolve(
          list(String.t()),
          list(integer()),
          list(integer()),
          list(integer())
        ) :: list({integer(), String.t()})
  defp extract_tables_to_resolve(strings, paths, path_dir, path_types) do
    # Iterate through path_types to find table paths (type 0)
    Enum.with_index(path_types)
    |> Enum.filter(fn {type, _} -> type == 0 end)
    |> Enum.map(fn {_, path_id} ->
      # Get the table name from the path
      table_idx = get_path_element(paths, path_dir, path_id, 0)
      table_name = Enum.at(strings, table_idx)

      {path_id, table_name}
    end)
  end

  # Extract relationships that need resolution
  @spec extract_relationships_to_resolve(
          list(String.t()),
          list(integer()),
          list(integer()),
          list(integer())
        ) :: list({integer(), {integer(), String.t()}})
  defp extract_relationships_to_resolve(strings, paths, path_dir, path_types) do
    # Iterate through path_types to find relationship paths (type 1)
    Enum.with_index(path_types)
    |> Enum.filter(fn {type, _} -> type == 1 end)
    |> Enum.map(fn {_, path_id} ->
      # Get path information for this relationship
      path_offset = Enum.at(path_dir, path_id)
      path_length = Enum.at(paths, path_offset)

      if path_length >= 2 do
        # Find the parent path ID by checking all table paths
        parent_path_id = find_parent_path_id(path_id, paths, path_dir, path_types)

        # Get the relationship field name (last element of the path)
        field_idx = get_path_element(paths, path_dir, path_id, path_length - 1)
        field_name = Enum.at(strings, field_idx)

        # Return the path ID, parent path ID, and field name for resolution
        {path_id, {parent_path_id, field_name}}
      else
        # Shouldn't happen for properly constructed relationships, but handle it gracefully
        {path_id, {-1, ""}}
      end
    end)
    |> Enum.filter(fn {_, {parent_id, _}} -> parent_id != -1 end)
  end

  # Find the parent path ID for a relationship path
  @spec find_parent_path_id(integer(), list(integer()), list(integer()), list(integer())) ::
          integer()
  defp find_parent_path_id(path_id, paths, path_dir, path_types) do
    # Get the current path offset
    current_offset = Enum.at(path_dir, path_id, -1)

    if current_offset == -1,
      do: -1,
      else: find_parent_path_with_offset(path_id, paths, path_dir, path_types, current_offset)
  end

  defp find_parent_path_with_offset(path_id, paths, path_dir, path_types, current_offset) do
    current_length = Enum.at(paths, current_offset, 0)

    # Get path elements except the last one (which should be the relationship field)
    current_path_elements =
      for i <- 0..(current_length - 2) do
        get_path_element(paths, path_dir, path_id, i)
      end

    # Find a table path that matches all elements of the parent path
    find_matching_table_path(current_path_elements, path_types, paths, path_dir)
  end

  # Find a table path that matches the parent path elements
  @spec find_matching_table_path(
          list(integer()),
          list(integer()),
          list(integer()),
          list(integer())
        ) ::
          integer()
  defp find_matching_table_path(current_path_elements, path_types, paths, path_dir) do
    Enum.with_index(path_types)
    # Only consider table paths
    |> Enum.filter(fn {type, _} -> type == 0 end)
    |> Enum.find_value(-1, &match_table_path(&1, current_path_elements, paths, path_dir))
  end

  # Check if a table path matches the parent path elements
  @spec match_table_path(
          {integer(), integer()},
          list(integer()),
          list(integer()),
          list(integer())
        ) ::
          integer() | false
  defp match_table_path({_, table_path_id}, current_path_elements, paths, path_dir) do
    # Get the table path offset
    table_offset = Enum.at(path_dir, table_path_id, -1)

    if table_offset == -1,
      do: false,
      else: check_path_match(table_path_id, current_path_elements, paths, path_dir, table_offset)
  end

  defp check_path_match(table_path_id, current_path_elements, paths, path_dir, table_offset) do
    table_length = Enum.at(paths, table_offset, 0)

    # Check if this could be a parent (has same length as parent path)
    if table_length != length(current_path_elements) do
      false
    else
      # Compare all elements
      table_path_elements =
        for i <- 0..(table_length - 1) do
          get_path_element(paths, path_dir, table_path_id, i)
        end

      # If all elements match, this is the parent path
      if table_path_elements == current_path_elements, do: table_path_id, else: false
    end
  end

  # Get an element from a path by path_id and index
  @spec get_path_element(list(integer()), list(integer()), integer(), integer()) :: integer()
  defp get_path_element(paths, path_dir, path_id, index) do
    offset = Enum.at(path_dir, path_id, -1)

    # Return -1 if we can't find the offset
    if offset == -1 do
      -1
    else
      length = Enum.at(paths, offset, 0)

      # Ensure the index is valid
      if index >= 0 and index < length do
        # +1 to skip the length field at the beginning of the path
        Enum.at(paths, offset + 1 + index, -1)
      else
        # Invalid index
        -1
      end
    end
  end

  # Resolve columns for tables
  @spec resolve_columns(map(), list(), list(String.t()), module(), map()) :: map()
  defp resolve_columns(resolved_tables, column_map, strings, resolver, context) do
    # Convert column_map to a more usable format
    column_map_by_table = build_column_map_by_table(column_map, strings)

    # For each resolved table, resolve its columns
    resolved_tables
    |> Enum.map(fn {path_id, table} ->
      {path_id,
       resolve_columns_for_table(
         path_id,
         table,
         column_map,
         column_map_by_table,
         resolver,
         context
       )}
    end)
    |> Enum.into(%{})
  end

  # Build a usable column map format
  @spec build_column_map_by_table(list(), list(String.t())) :: map()
  defp build_column_map_by_table(column_map, strings) do
    Enum.reduce(column_map, %{}, fn {table_idx, columns}, acc ->
      process_table_columns(table_idx, columns, strings, acc)
    end)
  end

  # Process table columns for column map
  @spec process_table_columns(integer(), list() | nil, list(String.t()), map()) :: map()
  defp process_table_columns(_table_idx, nil, _strings, acc), do: acc

  defp process_table_columns(table_idx, columns, strings, acc) do
    if Enum.empty?(columns) do
      acc
    else
      # Get column names
      column_names = Enum.map(columns, fn col_idx -> Enum.at(strings, col_idx) end)
      Map.put(acc, table_idx, column_names)
    end
  end

  # Resolve columns for a single table
  @spec resolve_columns_for_table(
          integer(),
          GraSQL.Schema.Table.t(),
          list(),
          map(),
          module(),
          map()
        ) :: list(GraSQL.Schema.Column.t())
  defp resolve_columns_for_table(
         path_id,
         table,
         _column_map,
         column_map_by_table,
         resolver,
         context
       ) do
    # The table index is the same as the path_id in the resolved_tables map
    # This provides O(1) lookup instead of scanning vectors
    table_idx = path_id

    # Get column names for this table from column_map
    column_names = Map.get(column_map_by_table, table_idx, [])

    # Get all available columns (from resolver and column map)
    combined_column_names = get_combined_column_names(column_names, table, resolver, context)

    # Resolve column attributes for each column
    Enum.map(combined_column_names, fn column_name ->
      create_column_with_attributes(column_name, table, resolver, context)
    end)
  end

  # Get combined column names from column map and resolver
  @spec get_combined_column_names(list(String.t()), GraSQL.Schema.Table.t(), module(), map()) ::
          list(String.t())
  defp get_combined_column_names(column_names, table, resolver, context) do
    # If resolver supports resolve_columns, get all available columns
    all_column_names =
      if function_exported?(resolver, :resolve_columns, 2) do
        resolver.resolve_columns(table, context)
      else
        column_names
      end

    # Union column names from both sources
    (column_names ++ all_column_names)
    |> Enum.uniq()
  end

  # Create a column struct with resolved attributes
  @spec create_column_with_attributes(String.t(), GraSQL.Schema.Table.t(), module(), map()) ::
          GraSQL.Schema.Column.t()
  defp create_column_with_attributes(column_name, table, resolver, context) do
    %Column{
      name: column_name,
      sql_type:
        resolve_column_attribute(:sql_type, column_name, table, resolver, context, "text"),
      is_required:
        resolve_column_attribute(:is_required, column_name, table, resolver, context, false),
      default_value:
        resolve_column_attribute(:default_value, column_name, table, resolver, context, nil)
    }
  end

  # Resolve a specific column attribute
  @spec resolve_column_attribute(
          atom(),
          String.t(),
          GraSQL.Schema.Table.t(),
          module(),
          map(),
          any()
        ) :: any()
  defp resolve_column_attribute(attribute, column_name, table, resolver, context, default) do
    if function_exported?(resolver, :resolve_column_attribute, 4) do
      resolver.resolve_column_attribute(attribute, column_name, table, context)
    else
      default
    end
  end

  # Build the resolution response in the format expected by Phase 3
  @spec build_resolution_response(String.t(), map(), map(), map(), list(), list()) :: map()
  defp build_resolution_response(query_id, tables, relationships, columns, operations, strings) do
    # Create full string table (including all strings from resolved entities)
    all_strings = collect_all_strings(tables, relationships, columns, strings)
    string_mapping = build_string_mapping(all_strings)

    # Convert tables to indexed format
    tables_indexed = build_tables_indexed(tables, string_mapping)

    # Convert relationships to indexed format
    {relationships_indexed, joins_indexed} =
      build_relationships_indexed(relationships, string_mapping)

    # Build path mapping
    path_map = build_path_map(tables, relationships)

    # Convert columns to indexed format
    columns_indexed = build_columns_indexed(columns, tables, string_mapping)

    # Return the complete response
    %{
      query_id: query_id,
      strings: all_strings,
      tables: tables_indexed,
      rels: relationships_indexed,
      joins: joins_indexed,
      path_map: path_map,
      cols: columns_indexed,
      # Include operations in the response
      ops: operations
    }
  end

  # Collect all strings needed for the response
  @spec collect_all_strings(map(), map(), map(), list()) :: list(String.t())
  defp collect_all_strings(tables, relationships, columns, strings) do
    # Start with existing strings
    base_strings = strings

    # Add strings from tables
    table_strings =
      tables
      |> Map.values()
      |> Enum.flat_map(fn table ->
        [table.schema, table.name] ++
          if table.__typename, do: [table.__typename], else: []
      end)

    # Add strings from relationships and join tables
    relationship_strings =
      relationships
      |> Map.values()
      |> Enum.flat_map(fn rel ->
        source_cols = rel.source_columns || []
        target_cols = rel.target_columns || []

        join_strings =
          case rel.join_table do
            nil ->
              []

            join ->
              [join.schema, join.name] ++
                (join.source_columns || []) ++
                (join.target_columns || [])
          end

        source_cols ++ target_cols ++ join_strings
      end)

    # Add strings from columns
    column_strings =
      columns
      |> Map.values()
      |> Enum.flat_map(fn cols ->
        Enum.flat_map(cols, fn col ->
          [col.name, col.sql_type] ++
            if col.default_value, do: [to_string(col.default_value)], else: []
        end)
      end)

    # Combine all strings and remove duplicates
    (base_strings ++ table_strings ++ relationship_strings ++ column_strings)
    |> Enum.uniq()
  end

  # Build mapping from string to index
  @spec build_string_mapping(list(String.t())) :: map()
  defp build_string_mapping(strings) do
    Enum.with_index(strings)
    |> Enum.into(%{})
  end

  # Convert tables to indexed format
  @spec build_tables_indexed(map(), map()) :: list(tuple())
  defp build_tables_indexed(tables, string_mapping) do
    tables
    |> Map.values()
    |> Enum.with_index()
    |> Enum.map(fn {table, _idx} ->
      schema_idx = Map.get(string_mapping, table.schema)
      name_idx = Map.get(string_mapping, table.name)

      typename_idx =
        if table.__typename do
          Map.get(string_mapping, table.__typename)
        else
          # Default to table name if no typename
          Map.get(string_mapping, table.name, 0)
        end

      {schema_idx, name_idx, typename_idx}
    end)
  end

  # Convert relationships to indexed format
  @spec build_relationships_indexed(map(), map()) :: {list(tuple()), list(tuple())}
  defp build_relationships_indexed(relationships, string_mapping) do
    # First, build a mapping from tables to their indices
    tables_with_index = build_table_index_mapping(relationships)

    # Process relationships
    {rels, joins} =
      relationships
      |> Map.values()
      |> Enum.with_index()
      |> Enum.map_reduce([], &process_relationship(&1, &2, tables_with_index, string_mapping))

    # Reverse joins to maintain original order since we've been prepending
    {rels, Enum.reverse(joins)}
  end

  # Build mapping from tables to indices
  @spec build_table_index_mapping(map()) :: map()
  defp build_table_index_mapping(relationships) do
    relationships
    |> Map.values()
    |> Enum.flat_map(fn rel -> [rel.source_table, rel.target_table] end)
    |> Enum.uniq_by(fn table -> {table.schema, table.name} end)
    |> Enum.with_index()
    |> Enum.into(%{}, fn {table, idx} -> {{table.schema, table.name}, idx} end)
  end

  # Process a single relationship
  @spec process_relationship(
          {GraSQL.Schema.Relationship.t(), integer()},
          list(tuple()),
          map(),
          map()
        ) :: {tuple(), list(tuple())}
  defp process_relationship({rel, _rel_idx}, join_acc, tables_with_index, string_mapping) do
    # Get table indices
    source_table_idx =
      Map.get(tables_with_index, {rel.source_table.schema, rel.source_table.name}, 0)

    target_table_idx =
      Map.get(tables_with_index, {rel.target_table.schema, rel.target_table.name}, 0)

    # Convert relationship type to code
    type_code = relationship_type_to_code(rel.type)

    # Convert source and target columns to indices
    src_col_idxs = columns_to_indices(rel.source_columns, string_mapping)
    tgt_col_idxs = columns_to_indices(rel.target_columns, string_mapping)

    # Handle join table if present
    {join_table_idx, new_join_acc} = process_join_table(rel.join_table, join_acc, string_mapping)

    # Return relationship entry and updated joins
    {{source_table_idx, target_table_idx, type_code, join_table_idx, src_col_idxs, tgt_col_idxs},
     new_join_acc}
  end

  # Convert relationship type to numeric code
  @spec relationship_type_to_code(GraSQL.Schema.Relationship.relationship_type()) :: integer()
  defp relationship_type_to_code(type) do
    case type do
      :belongs_to -> 0
      :has_one -> 1
      :has_many -> 2
      :many_to_many -> 3
      # Default
      _ -> 0
    end
  end

  # Convert column names to indices in the string mapping
  @spec columns_to_indices(list(String.t()) | nil, map()) :: list(integer())
  defp columns_to_indices(columns, string_mapping) do
    (columns || [])
    |> Enum.map(fn col -> Map.get(string_mapping, col) end)
  end

  # Process join table for a relationship
  @spec process_join_table(GraSQL.Schema.JoinTable.t() | nil, list(tuple()), map()) ::
          {integer(), list(tuple())}
  defp process_join_table(nil, join_acc, _string_mapping) do
    {-1, join_acc}
  end

  defp process_join_table(join, join_acc, string_mapping) do
    # Create join table entry
    schema_idx = Map.get(string_mapping, join.schema)
    name_idx = Map.get(string_mapping, join.name)

    # Convert column names to indices
    src_join_col_idxs = columns_to_indices(join.source_columns, string_mapping)
    tgt_join_col_idxs = columns_to_indices(join.target_columns, string_mapping)

    # Create the join table entry tuple
    join_entry = create_join_entry(schema_idx, name_idx, src_join_col_idxs, tgt_join_col_idxs)

    # Add to joins and return index - prepend for O(1) instead of append O(n)
    {length(join_acc), [join_entry | join_acc]}
  end

  # Create a join table entry tuple
  @spec create_join_entry(integer(), integer(), list(integer()), list(integer())) :: tuple()
  defp create_join_entry(schema_idx, name_idx, src_col_idxs, tgt_col_idxs) do
    {schema_idx, name_idx, src_col_idxs, tgt_col_idxs}
  end

  # Build path mapping
  @spec build_path_map(map(), map()) :: list(tuple())
  defp build_path_map(tables, relationships) do
    # For each path ID, map to either a table or relationship entity using with_index
    # to ensure deterministic indexing regardless of path_id values
    table_maps =
      tables
      |> Enum.with_index()
      |> Enum.map(fn {{path_id, _table}, idx} -> {path_id, {0, idx}} end)

    relationship_maps =
      relationships
      |> Enum.with_index()
      |> Enum.map(fn {{path_id, _rel}, idx} -> {path_id, {1, idx}} end)

    # Combine and sort by path_id for O(1) access by path_id
    (table_maps ++ relationship_maps)
    |> Enum.sort_by(fn {path_id, _} -> path_id end)
    |> Enum.map(fn {_, entry} -> entry end)
  end

  # Convert columns to indexed format
  @spec build_columns_indexed(map(), map(), map()) :: list(tuple())
  defp build_columns_indexed(columns, tables, string_mapping) do
    # Build a mapping from tables to their indices
    table_mapping = build_table_to_index_mapping(tables)

    # Process all columns
    columns
    |> Enum.flat_map(fn {path_id, cols} ->
      process_columns_for_path_id(path_id, cols, tables, table_mapping, string_mapping)
    end)
  end

  # Build mapping from tables to their indices
  @spec build_table_to_index_mapping(map()) :: map()
  defp build_table_to_index_mapping(tables) do
    tables
    |> Map.values()
    |> Enum.with_index()
    |> Enum.into(%{}, fn {table, idx} -> {{table.schema, table.name}, idx} end)
  end

  # Process columns for a specific path_id
  @spec process_columns_for_path_id(
          integer(),
          list(GraSQL.Schema.Column.t()),
          map(),
          map(),
          map()
        ) :: list(tuple())
  defp process_columns_for_path_id(path_id, cols, tables, table_mapping, string_mapping) do
    # Get the table for this path
    table = Map.get(tables, path_id)

    if table == nil,
      do: [],
      else: process_columns_for_table(cols, table, table_mapping, string_mapping)
  end

  # Process columns for a specific table
  @spec process_columns_for_table(
          list(GraSQL.Schema.Column.t()),
          GraSQL.Schema.Table.t(),
          map(),
          map()
        ) :: list(tuple())
  defp process_columns_for_table(cols, table, table_mapping, string_mapping) do
    table_idx = Map.get(table_mapping, {table.schema, table.name}, 0)

    # Process each column
    Enum.map(cols, fn col ->
      convert_column_to_indices(col, table_idx, string_mapping)
    end)
  end

  # Convert a column to indexed format
  @spec convert_column_to_indices(GraSQL.Schema.Column.t(), integer(), map()) :: tuple()
  defp convert_column_to_indices(col, table_idx, string_mapping) do
    name_idx = Map.get(string_mapping, col.name)
    type_idx = Map.get(string_mapping, col.sql_type)
    default_val_idx = get_default_value_index(col.default_value, string_mapping)

    {table_idx, name_idx, type_idx, default_val_idx}
  end

  # Get the index for a column's default value
  @spec get_default_value_index(any(), map()) :: integer()
  defp get_default_value_index(nil, _string_mapping), do: -1

  defp get_default_value_index(default_value, string_mapping) do
    Map.get(string_mapping, to_string(default_value), -1)
  end

  # Get the resolver from cache
  @spec get_cached_resolver() :: module()
  defp get_cached_resolver do
    case GraSQL.SchemaResolverCache.get_resolver() do
      {:ok, resolver} -> resolver
      {:error, reason} -> raise "Failed to get schema resolver: #{reason}"
    end
  end
end
