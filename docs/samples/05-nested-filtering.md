# GraphQL Sample 5: Nested Filtering

This sample demonstrates a GraphQL query with filtering on a nested relationship.

## GraphQL Query

```graphql
{
  users(where: { posts: { title: { _like: "%test%" } } }) {
    id
    name
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "3b5d7a9c1e8f2d0b",
  "strings": ["users", "id", "name", "posts", "title"],
  "paths": [1, 0, 2, 0, 3],
  "path_dir": [0, 2],
  "path_types": [0, 1],
  "cols": [[0, [1, 2]]],
  "ops": [[0, 0]]
}
```

- Note: The `posts` path is included because it's referenced in the filter, even though posts aren't in the selection set.
- The filter condition details will be extracted from the document pointer in Phase 3.

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "3b5d7a9c1e8f2d0b",
  "strings": [
    "users",
    "id",
    "name",
    "posts",
    "title",
    "public",
    "User",
    "Post",
    "INTEGER",
    "VARCHAR(255)",
    "TEXT",
    "user_id"
  ],
  "tables": [
    [5, 0, 6],
    [5, 3, 7]
  ],
  "rels": [[0, 1, 2, -1, [1], [11]]],
  "joins": [],
  "path_map": [
    [0, 0],
    [1, 0]
  ],
  "cols": [
    [0, 1, 8, -1],
    [0, 2, 9, -1],
    [1, 4, 10, -1],
    [1, 11, 8, -1]
  ],
  "ops": [[0, 0]]
}
```

- Both tables and the relationship are resolved even though only users fields are selected
- This is necessary because the filter condition references the posts table

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
WHERE EXISTS (
  SELECT 1
  FROM "public"."posts" AS t1
  WHERE t1.user_id = t0.id
    AND t1.title LIKE $1
)
```

## Parameters

```json
["%test%"]
```

The SQL query returns data in the exact shape requested by the GraphQL query:

- Creates a JSON object with a "users" key at the top level
- The value is an array of user objects with id and name properties
- The WHERE clause uses EXISTS with a subquery to filter users based on their posts
- Only returns users who have at least one post with a title containing "test"
- The parameter $1 is set to the LIKE pattern value "%test%"
