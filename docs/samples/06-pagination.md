# GraphQL Sample 6: Pagination

This sample demonstrates a GraphQL query with pagination (limit and offset).

## GraphQL Query

```graphql
{
  users(limit: 10, offset: 20) {
    id
    name
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "2a4c6e8b0d1f3a5c",
  "strings": ["users", "id", "name"],
  "paths": [1, 0],
  "path_dir": [0],
  "path_types": [0],
  "cols": [[0, [1, 2]]],
  "ops": [[0, 0]]
}
```

- Note: The pagination parameters are not included in the ResolutionRequest but will be extracted from the document pointer in Phase 3.

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "2a4c6e8b0d1f3a5c",
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
FROM "public"."users" AS t0
WHERE (true)
LIMIT $1 OFFSET $2
```

## Parameters

```json
[10, 20]
```

The SQL query returns data in the exact shape requested by the GraphQL query:

- Creates a JSON object with a "users" key at the top level
- The value is an array of user objects with id and name properties
- Applies LIMIT and OFFSET for pagination
- The parameters $1 and $2 are set to the limit and offset values
- LIMIT 10 returns at most 10 records
- OFFSET 20 skips the first 20 records
