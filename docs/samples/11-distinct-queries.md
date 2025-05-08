# GraphQL Sample 11: Distinct Queries

This sample demonstrates a GraphQL query that requests distinct values from a table.

## GraphQL Query

```graphql
{
  users(distinct_on: name) {
    id
    name
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "1a3c5e7b9d2f4e6b",
  "strings": ["users", "id", "name"],
  "paths": [1, 0],
  "path_dir": [0],
  "path_types": [0],
  "cols": [[0, [1, 2]]],
  "ops": [[0, 0]]
}
```

- Note: The distinct_on parameter is not included in the ResolutionRequest but will be extracted from the document pointer in Phase 3.

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "1a3c5e7b9d2f4e6b",
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
FROM (
  SELECT DISTINCT ON (t0.name) t0.id, t0.name
  FROM "public"."users" AS t0
  WHERE (true)
  ORDER BY t0.name
) AS t0
```

## Parameters

```json
[]
```

The SQL query returns data in the exact shape requested by the GraphQL query:

- Creates a JSON object with a "users" key at the top level
- The value is an array of user objects with id and name properties
- Uses a subquery with DISTINCT ON to get unique rows based on the name field
- The ORDER BY clause is required when using DISTINCT ON in PostgreSQL
- Returns the exact hierarchical structure matching the GraphQL query
