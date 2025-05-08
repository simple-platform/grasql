# GraphQL Sample 15: Insert Mutation

This sample demonstrates a GraphQL mutation that inserts a new record.

## GraphQL Query

```graphql
mutation {
  insert_users_one(
    object: { name: "John Doe", email: "john@example.com", age: 30 }
  ) {
    id
    name
    email
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "6a8c0e2d4f9b1a3c",
  "strings": ["insert_users_one", "id", "name", "email", "age"],
  "paths": [1, 0],
  "path_dir": [0],
  "path_types": [0],
  "cols": [[0, [1, 2, 3]]],
  "ops": [[0, 1]]
}
```

- Note: The operation type is 1 for mutation (0 for query)
- The insert object is not included in the ResolutionRequest but will be extracted from the document pointer in Phase 3.

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "6a8c0e2d4f9b1a3c",
  "strings": [
    "insert_users_one",
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
  "tables": [[5, 6, 7]],
  "rels": [],
  "joins": [],
  "path_map": [[0, 0]],
  "cols": [
    [0, 1, 8, -1],
    [0, 2, 9, -1],
    [0, 3, 10, -1],
    [0, 4, 8, -1]
  ],
  "ops": [[0, 1]]
}
```

## Expected SQL

```sql
WITH inserted AS (
  INSERT INTO "public"."users" (name, email, age)
  VALUES ($1, $2, $3)
  RETURNING id, name, email
)
SELECT json_build_object(
  'insert_users_one', (
    SELECT json_build_object(
      'id', inserted.id,
      'name', inserted.name,
      'email', inserted.email
    )
    FROM inserted
  )
) AS result
```

## Parameters

```json
["John Doe", "john@example.com", 30]
```

The SQL query returns data in the exact shape requested by the GraphQL query:

- Uses a CTE (WITH clause) to perform the INSERT operation and capture the returned values
- Creates a JSON object with an "insert_users_one" key at the top level
- The value is an object containing the requested fields from the inserted record
- Properly handles the insert values as parameters
- Returns the newly created record's fields as specified in the selection set
