# GraphQL Sample 19: Delete Mutation

This sample demonstrates a GraphQL mutation that deletes a record by ID.

## GraphQL Query

```graphql
mutation {
  delete_users_by_pk(id: 123) {
    id
    name
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "2d4f6a8c0e2b4d6f",
  "strings": ["delete_users_by_pk", "id", "name"],
  "paths": [1, 0],
  "path_dir": [0],
  "path_types": [0],
  "cols": [[0, [1, 2]]],
  "ops": [[0, 1]]
}
```

- Note: The operation type is 1 for mutation
- The primary key is not included in the ResolutionRequest but will be extracted from the document pointer in Phase 3.

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "2d4f6a8c0e2b4d6f",
  "strings": [
    "delete_users_by_pk",
    "id",
    "name",
    "public",
    "users",
    "User",
    "INTEGER",
    "VARCHAR(255)"
  ],
  "tables": [[3, 4, 5]],
  "rels": [],
  "joins": [],
  "path_map": [[0, 0]],
  "cols": [
    [0, 1, 6, -1],
    [0, 2, 7, -1]
  ],
  "ops": [[0, 1]]
}
```

## Expected SQL

```sql
WITH deleted AS (
  DELETE FROM "public"."users"
  WHERE id = $1
  RETURNING id, name
)
SELECT json_build_object(
  'delete_users_by_pk', (
    SELECT json_build_object(
      'id', deleted.id,
      'name', deleted.name
    )
    FROM deleted
  )
) AS result
```

## Parameters

```json
[123]
```

The SQL query returns data in the exact shape requested by the GraphQL query:

- Uses a CTE (WITH clause) to perform the DELETE operation and capture the returned values
- Creates a JSON object with a "delete_users_by_pk" key at the top level
- The value is an object containing the requested fields from the deleted record
- Uses a WHERE clause with the primary key for precise record selection
- Properly handles the ID as a parameter
- Returns the deleted record's fields as specified in the selection set
