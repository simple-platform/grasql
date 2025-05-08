# GraphQL Sample 12: Complex Boolean Logic

This sample demonstrates a GraphQL query with complex boolean logic in filter conditions.

## GraphQL Query

```graphql
{
  users(
    where: {
      _or: [
        { name: { _like: "%John%" } }
        { _and: [{ age: { _gt: 30 } }, { active: { _eq: true } }] }
      ]
    }
  ) {
    id
    name
    age
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "9c1e5a7b3d8f2e4a",
  "strings": ["users", "id", "name", "age", "active"],
  "paths": [1, 0],
  "path_dir": [0],
  "path_types": [0],
  "cols": [[0, [1, 2, 3]]],
  "ops": [[0, 0]]
}
```

- Note: The filter conditions are not included in the ResolutionRequest but will be extracted from the document pointer in Phase 3.

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "9c1e5a7b3d8f2e4a",
  "strings": [
    "users",
    "id",
    "name",
    "age",
    "active",
    "public",
    "User",
    "INTEGER",
    "VARCHAR(255)",
    "BOOLEAN"
  ],
  "tables": [[5, 0, 6]],
  "rels": [],
  "joins": [],
  "path_map": [[0, 0]],
  "cols": [
    [0, 1, 7, -1],
    [0, 2, 8, -1],
    [0, 3, 7, -1],
    [0, 4, 9, -1]
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
      'name', t0.name,
      'age', t0.age
    )
  ), '[]')
) AS result
FROM "public"."users" AS t0
WHERE (
  (t0.name LIKE $1)
  OR
  (t0.age > $2 AND t0.active = $3)
)
```

## Parameters

```json
["%John%", 30, true]
```

The SQL query returns data in the exact shape requested by the GraphQL query:

- Creates a JSON object with a "users" key at the top level
- The value is an array of user objects with id, name, and age properties
- The WHERE clause implements the complex boolean logic from the GraphQL query
- Translates \_or and \_and into SQL OR and AND operators
- Translates \_like, \_gt, and \_eq into SQL LIKE, >, and = operators
- The parameters are properly extracted and used in the SQL query
