# GraphQL Sample 16: Batch Insert Mutation

This sample demonstrates a GraphQL mutation that inserts multiple records in a batch.

## GraphQL Query

```graphql
mutation {
  insert_users(
    objects: [
      { name: "John Doe", email: "john@example.com", age: 30 }
      { name: "Jane Smith", email: "jane@example.com", age: 28 }
    ]
  ) {
    affected_rows
    returning {
      id
      name
    }
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "5b7d9f1a3c5e8b2d",
  "strings": [
    "insert_users",
    "affected_rows",
    "returning",
    "id",
    "name",
    "email",
    "age"
  ],
  "paths": [1, 0],
  "path_dir": [0],
  "path_types": [0],
  "cols": [[0, [3, 4]]],
  "ops": [[0, 1]]
}
```

- Note: The operation type is 1 for mutation
- The batch insert objects are not included in the ResolutionRequest but will be extracted from the document pointer in Phase 3.

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "5b7d9f1a3c5e8b2d",
  "strings": [
    "insert_users",
    "affected_rows",
    "returning",
    "id",
    "name",
    "email",
    "age",
    "public",
    "users",
    "User",
    "INTEGER",
    "VARCHAR(255)",
    "TEXT"
  ],
  "tables": [[7, 8, 9]],
  "rels": [],
  "joins": [],
  "path_map": [[0, 0]],
  "cols": [
    [0, 3, 10, -1],
    [0, 4, 11, -1],
    [0, 5, 12, -1],
    [0, 6, 10, -1]
  ],
  "ops": [[0, 1]]
}
```

## Expected SQL

```sql
WITH inserted AS (
  INSERT INTO "public"."users" (name, email, age)
  VALUES
    ($1, $2, $3),
    ($4, $5, $6)
  RETURNING id, name
)
SELECT json_build_object(
  'insert_users', json_build_object(
    'affected_rows', (SELECT COUNT(*) FROM inserted),
    'returning', COALESCE((
      SELECT json_agg(
        json_build_object(
          'id', inserted.id,
          'name', inserted.name
        )
      )
      FROM inserted
    ), '[]')
  )
) AS result
```

## Parameters

```json
["John Doe", "john@example.com", 30, "Jane Smith", "jane@example.com", 28]
```

The SQL query returns data in the exact shape requested by the GraphQL query:

- Uses a CTE (WITH clause) to perform the batch INSERT operation and capture the returned values
- Creates a JSON object with an "insert_users" key at the top level
- The value is an object with "affected_rows" and "returning" properties
- The "affected_rows" property contains the count of inserted records
- The "returning" property contains an array of objects with the requested fields
- Properly handles multiple sets of insert values as parameters
- Returns the newly created records' fields as specified in the selection set
