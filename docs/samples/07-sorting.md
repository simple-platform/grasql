# GraphQL Sample 7: Sorting

This sample demonstrates a GraphQL query with sorting.

## GraphQL Query

```graphql
{
  users(order_by: { name: asc }) {
    id
    name
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "1b3d5f7a9c2e4b6d",
  "strings": ["users", "id", "name"],
  "paths": [1, 0],
  "path_dir": [0],
  "path_types": [0],
  "cols": [[0, [1, 2]]],
  "ops": [[0, 0]]
}
```

- Note: The sorting parameters are not included in the ResolutionRequest but will be extracted from the document pointer in Phase 3.

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "1b3d5f7a9c2e4b6d",
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
    ORDER BY t0.name ASC
  ), '[]')
) AS result
FROM "public"."users" AS t0
WHERE (true)
```

## Parameters

```json
[]
```

The SQL query returns data in the exact shape requested by the GraphQL query:

- Creates a JSON object with a "users" key at the top level
- The value is an array of user objects with id and name properties
- The ORDER BY clause is applied inside the json_agg function to ensure the order is preserved in the JSON array
- Sorts the results by the "name" column in ascending order
