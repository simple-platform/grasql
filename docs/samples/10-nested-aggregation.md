# GraphQL Sample 10: Nested Aggregation

This sample demonstrates a GraphQL query with aggregation on a nested relationship.

## GraphQL Query

```graphql
{
  users {
    id
    name
    posts_aggregate {
      aggregate {
        count
      }
    }
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "2d4f6b8a0c2e4d6f",
  "strings": ["users", "id", "name", "posts_aggregate", "aggregate", "count"],
  "paths": [1, 0, 2, 0, 3],
  "path_dir": [0, 2],
  "path_types": [0, 0],
  "cols": [[0, [1, 2]]],
  "ops": [[0, 0]]
}
```

- The path structure includes the users table and the posts_aggregate table as a separate path.

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "2d4f6b8a0c2e4d6f",
  "strings": [
    "users",
    "id",
    "name",
    "posts_aggregate",
    "aggregate",
    "count",
    "public",
    "User",
    "Post",
    "INTEGER",
    "VARCHAR(255)",
    "user_id"
  ],
  "tables": [
    [6, 0, 7],
    [6, 3, 8]
  ],
  "rels": [[0, 1, 2, -1, [1], [11]]],
  "joins": [],
  "path_map": [
    [0, 0],
    [0, 1]
  ],
  "cols": [
    [0, 1, 9, -1],
    [0, 2, 10, -1],
    [1, 11, 9, -1]
  ],
  "ops": [[0, 0]]
}
```

- Tables include users and posts tables
- The relationship between users and posts is defined with a foreign key
- The path_map maps both paths to tables (not relationships)

## Expected SQL

```sql
SELECT json_build_object(
  'users', COALESCE(json_agg(
    json_build_object(
      'id', t0.id,
      'name', t0.name,
      'posts_aggregate', json_build_object(
        'aggregate', json_build_object(
          'count', (
            SELECT COUNT(*)
            FROM "public"."posts" AS t1
            WHERE t1.user_id = t0.id
          )
        )
      )
    )
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
- Each user object contains "id", "name", and "posts_aggregate" fields
- The "posts_aggregate" field contains an "aggregate" object with a "count" property
- Uses a correlated subquery to count the number of posts for each user
- The structure exactly matches the GraphQL query's hierarchical structure
