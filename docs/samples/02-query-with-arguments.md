# GraphQL Sample 2: Query with Arguments (by ID)

This sample demonstrates a GraphQL query that retrieves a specific record by ID.

## GraphQL Query

```graphql
{
  user(id: 123) {
    id
    name
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "7a8c54b2e9f10d12",
  "strings": ["user", "id", "name"],
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
- `path_types`: Type of path (0 = table)
- `cols`: Column map [table_idx, [column_idx1, column_idx2, ...]]
- `ops`: Operations (root field index, operation type) where 0 = query

Note: The ID argument is not included in the strings array but will be handled in Phase 3 SQL generation directly from the document pointer.

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "7a8c54b2e9f10d12",
  "strings": [
    "user",
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
  'user', (
    SELECT json_build_object(
      'id', t0.id,
      'name', t0.name
    )
    FROM "public"."user" AS t0
    WHERE t0.id = $1
    LIMIT 1
  )
) AS result
```

## Parameters

```json
[123]
```

The SQL query returns data in the exact shape requested by the GraphQL query:

- Creates a JSON object with a key "user" (matching the GraphQL field name)
- The value is a single user object with id and name properties
- Uses a subquery with LIMIT 1 to ensure only one record is returned
- The parameter $1 is set to the ID value (123)
