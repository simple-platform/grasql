# GraphQL Sample 1: Simple Query

This sample demonstrates a basic GraphQL query that retrieves fields from a single table.

## GraphQL Query

```graphql
{
  users {
    id
    name
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "9f8b20e3d7c64e7a",
  "strings": ["users", "id", "name"],
  "paths": [1, 0],
  "path_dir": [0],
  "path_types": [0],
  "cols": [[0, [1, 2]]],
  "ops": [[0, 0]]
}
```

- `query_id`: Unique identifier for the query
- `strings`: All field names used in the query
- `paths`: Encoded path information, with the first value being the length
- `path_dir`: Directory mapping of path_id to offset in paths array
- `path_types`: Type of path (0 = table, 1 = relationship)
- `cols`: Column map [table_idx, [column_idx1, column_idx2, ...]]
- `ops`: Operations (root field index, operation type) where 0 = query

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "9f8b20e3d7c64e7a",
  "strings": [
    "users",
    "id",
    "name",
    "public",
    "User",
    "INTEGER",
    "VARCHAR(255)"
  ],
  "tables": [[3, 0, 4]],
  "rels": [],
  "joins": [],
  "path_map": [[0, 0]],
  "cols": [
    [0, 1, 5, -1],
    [0, 2, 6, -1]
  ],
  "ops": [[0, 0]]
}
```

- `tables`: [schema_idx, name_idx, typename_idx]
- `rels`: Empty as there are no relationships
- `joins`: Empty as there are no many-to-many relationships
- `path_map`: [entity_type, entity_idx] - maps path_id to table or relationship
- `cols`: [table_idx, name_idx, type_idx, default_val_idx]

## Expected SQL

```sql
SELECT json_build_object(
  'users', COALESCE(json_agg(
    json_build_object(
      'id', t0.id,
      'name', t0.name
    )
  ), '[]')
) AS result
FROM "public"."users" AS t0
WHERE (true)
```

## Parameters

```json
[]
```

The SQL query returns the data in the exact shape requested by the GraphQL query:

- Creates a JSON object with a key "users" (matching the GraphQL field name)
- The value is an array of user objects with id and name fields
- Uses COALESCE to ensure an empty array is returned if no users are found, not NULL
