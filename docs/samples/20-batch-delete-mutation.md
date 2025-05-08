# GraphQL Sample 20: Batch Delete Mutation

This sample demonstrates a GraphQL mutation that deletes multiple records based on a filter condition.

## GraphQL Query

```graphql
mutation {
  delete_users(
    where: {
      last_login: { _lt: "2022-01-01T00:00:00Z" }
      active: { _eq: false }
    }
  ) {
    affected_rows
    returning {
      id
      name
      email
    }
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "1c3e5b7d9f1a3c5e",
  "strings": [
    "delete_users",
    "affected_rows",
    "returning",
    "id",
    "name",
    "email",
    "last_login",
    "active"
  ],
  "paths": [1, 0],
  "path_dir": [0],
  "path_types": [0],
  "cols": [[0, [3, 4, 5]]],
  "ops": [[0, 1]]
}
```

- Note: The operation type is 1 for mutation
- The filter conditions are not included in the ResolutionRequest but will be extracted from the document pointer in Phase 3.

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "1c3e5b7d9f1a3c5e",
  "strings": [
    "delete_users",
    "affected_rows",
    "returning",
    "id",
    "name",
    "email",
    "last_login",
    "active",
    "public",
    "users",
    "User",
    "INTEGER",
    "VARCHAR(255)",
    "TEXT",
    "TIMESTAMP",
    "BOOLEAN"
  ],
  "tables": [[8, 9, 10]],
  "rels": [],
  "joins": [],
  "path_map": [[0, 0]],
  "cols": [
    [0, 3, 11, -1],
    [0, 4, 12, -1],
    [0, 5, 13, -1],
    [0, 6, 14, -1],
    [0, 7, 15, -1]
  ],
  "ops": [[0, 1]]
}
```

## Expected SQL

```sql
WITH deleted AS (
  DELETE FROM "public"."users"
  WHERE last_login < $1 AND active = $2
  RETURNING id, name, email
)
SELECT json_build_object(
  'delete_users', json_build_object(
    'affected_rows', (SELECT COUNT(*) FROM deleted),
    'returning', COALESCE((
      SELECT json_agg(
        json_build_object(
          'id', deleted.id,
          'name', deleted.name,
          'email', deleted.email
        )
      )
      FROM deleted
    ), '[]')
  )
) AS result
```

## Parameters

```json
["2022-01-01T00:00:00Z", false]
```

The SQL query returns data in the exact shape requested by the GraphQL query:

- Uses a CTE (WITH clause) to perform the batch DELETE operation and capture the returned values
- Creates a JSON object with a "delete_users" key at the top level
- The value is an object with "affected_rows" and "returning" properties
- The "affected_rows" property contains the count of deleted records
- The "returning" property contains an array of objects with the requested fields
- Applies complex filter conditions using AND logic to target specific records
- Translates \_lt to < and \_eq to = in the SQL WHERE clause
- Properly handles the filter values as parameters
- Returns the deleted records' fields as specified in the selection set
