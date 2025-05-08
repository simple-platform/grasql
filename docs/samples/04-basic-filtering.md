# GraphQL Sample 4: Basic Filtering

This sample demonstrates a GraphQL query with filtering conditions.

## GraphQL Query

```graphql
{
  users(where: { name: { _eq: "John" } }) {
    id
    name
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "4c6d8b2a9e0f3a1c",
  "strings": ["users", "id", "name"],
  "paths": [1, 0],
  "path_dir": [0],
  "path_types": [0],
  "cols": [[0, [1, 2]]],
  "ops": [[0, 0]]
}
```

- Note: The filter conditions are not included in the ResolutionRequest but will be extracted from the document pointer in Phase 3.

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "4c6d8b2a9e0f3a1c",
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

- Response includes column information necessary for the filter operations, even though the filter itself is handled in Phase 3.

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
WHERE t0.name = $1
```

## Parameters

```json
["John"]
```

The SQL query returns data in the exact shape requested by the GraphQL query:

- Creates a JSON object with a "users" key at the top level
- The value is an array of user objects with id and name properties
- The WHERE clause applies the filter condition from the GraphQL query
- The parameter $1 is set to the filter value "John"
