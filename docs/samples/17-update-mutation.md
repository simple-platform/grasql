# GraphQL Sample 17: Update Mutation

This sample demonstrates a GraphQL mutation that updates a record by ID.

## GraphQL Query

```graphql
mutation {
  update_users_by_pk(
    pk_columns: { id: 123 }
    _set: { name: "Updated Name", email: "updated@example.com" }
  ) {
    id
    name
    email
    updated_at
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "4a6c8e0b2d4f6a8c",
  "strings": ["update_users_by_pk", "id", "name", "email", "updated_at"],
  "paths": [1, 0],
  "path_dir": [0],
  "path_types": [0],
  "cols": [[0, [1, 2, 3, 4]]],
  "ops": [[0, 1]]
}
```

- Note: The operation type is 1 for mutation
- The update values and the primary key are not included in the ResolutionRequest but will be extracted from the document pointer in Phase 3.

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "4a6c8e0b2d4f6a8c",
  "strings": [
    "update_users_by_pk",
    "id",
    "name",
    "email",
    "updated_at",
    "public",
    "users",
    "User",
    "INTEGER",
    "VARCHAR(255)",
    "TEXT",
    "TIMESTAMP"
  ],
  "tables": [[5, 6, 7]],
  "rels": [],
  "joins": [],
  "path_map": [[0, 0]],
  "cols": [
    [0, 1, 8, -1],
    [0, 2, 9, -1],
    [0, 3, 10, -1],
    [0, 4, 11, -1]
  ],
  "ops": [[0, 1]]
}
```

## Expected SQL

```sql
WITH updated AS (
  UPDATE "public"."users"
  SET
    name = $1,
    email = $2,
    updated_at = CURRENT_TIMESTAMP
  WHERE id = $3
  RETURNING id, name, email, updated_at
)
SELECT json_build_object(
  'update_users_by_pk', (
    SELECT json_build_object(
      'id', updated.id,
      'name', updated.name,
      'email', updated.email,
      'updated_at', updated.updated_at
    )
    FROM updated
  )
) AS result
```

## Parameters

```json
["Updated Name", "updated@example.com", 123]
```

The SQL query returns data in the exact shape requested by the GraphQL query:

- Uses a CTE (WITH clause) to perform the UPDATE operation and capture the returned values
- Creates a JSON object with an "update_users_by_pk" key at the top level
- The value is an object containing the requested fields from the updated record
- Automatically updates the updated_at timestamp when performing the update
- Uses a WHERE clause with the primary key for precise record selection
- Properly handles the update values and ID as parameters
- Returns the updated record's fields as specified in the selection set
