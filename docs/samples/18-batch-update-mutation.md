# GraphQL Sample 18: Batch Update Mutation

This sample demonstrates a GraphQL mutation that updates multiple records based on a filter condition.

## GraphQL Query

```graphql
mutation {
  update_users(
    where: { active: { _eq: false } }
    _set: { active: true, updated_at: "2023-06-15T12:00:00Z" }
  ) {
    affected_rows
    returning {
      id
      name
      active
      updated_at
    }
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "3b5d7f9a1c3e5b7d",
  "strings": [
    "update_users",
    "affected_rows",
    "returning",
    "id",
    "name",
    "active",
    "updated_at"
  ],
  "paths": [1, 0],
  "path_dir": [0],
  "path_types": [0],
  "cols": [[0, [3, 4, 5, 6]]],
  "ops": [[0, 1]]
}
```

- Note: The operation type is 1 for mutation
- The update values and filter conditions are not included in the ResolutionRequest but will be extracted from the document pointer in Phase 3.

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "3b5d7f9a1c3e5b7d",
  "strings": [
    "update_users",
    "affected_rows",
    "returning",
    "id",
    "name",
    "active",
    "updated_at",
    "public",
    "users",
    "User",
    "INTEGER",
    "VARCHAR(255)",
    "BOOLEAN",
    "TIMESTAMP"
  ],
  "tables": [[7, 8, 9]],
  "rels": [],
  "joins": [],
  "path_map": [[0, 0]],
  "cols": [
    [0, 3, 10, -1],
    [0, 4, 11, -1],
    [0, 5, 12, -1],
    [0, 6, 13, -1]
  ],
  "ops": [[0, 1]]
}
```

## Expected SQL

```sql
WITH updated AS (
  UPDATE "public"."users"
  SET
    active = $1,
    updated_at = $2
  WHERE active = $3
  RETURNING id, name, active, updated_at
)
SELECT json_build_object(
  'update_users', json_build_object(
    'affected_rows', (SELECT COUNT(*) FROM updated),
    'returning', COALESCE((
      SELECT json_agg(
        json_build_object(
          'id', updated.id,
          'name', updated.name,
          'active', updated.active,
          'updated_at', updated.updated_at
        )
      )
      FROM updated
    ), '[]')
  )
) AS result
```

## Parameters

```json
[true, "2023-06-15T12:00:00Z", false]
```

The SQL query returns data in the exact shape requested by the GraphQL query:

- Uses a CTE (WITH clause) to perform the batch UPDATE operation and capture the returned values
- Creates a JSON object with an "update_users" key at the top level
- The value is an object with "affected_rows" and "returning" properties
- The "affected_rows" property contains the count of updated records
- The "returning" property contains an array of objects with the requested fields
- Applies the filter condition to update only records where active = false
- Sets the active and updated_at fields as specified in the \_set parameter
- Properly handles the update values and filter condition as parameters
- Returns the updated records' fields as specified in the selection set
