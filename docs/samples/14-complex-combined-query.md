# GraphQL Sample 14: Complex Combined Query

This sample demonstrates a complex GraphQL query combining multiple features: relationships, filtering, sorting, and pagination.

## GraphQL Query

```graphql
{
  users(
    where: { age: { _gt: 21 } }
    order_by: { name: asc }
    limit: 5
    offset: 10
  ) {
    id
    name
    posts(
      where: { published: { _eq: true } }
      order_by: { created_at: desc }
      limit: 3
    ) {
      title
      content
    }
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "7b9d1f3e5a2c8d4e",
  "strings": [
    "users",
    "id",
    "name",
    "posts",
    "title",
    "content",
    "age",
    "published",
    "created_at"
  ],
  "paths": [1, 0, 2, 0, 3],
  "path_dir": [0, 2],
  "path_types": [0, 1],
  "cols": [
    [0, [1, 2, 6]],
    [3, [4, 5, 7]]
  ],
  "ops": [[0, 0]]
}
```

- The path structure includes the users table and the posts relationship.
- Columns include fields used in selections and filter conditions.
- Note that "created_at" is present in strings but not included in columns since it's only used in order_by and doesn't need resolution.

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "7b9d1f3e5a2c8d4e",
  "strings": [
    "users",
    "id",
    "name",
    "posts",
    "title",
    "content",
    "age",
    "published",
    "created_at",
    "public",
    "User",
    "Post",
    "INTEGER",
    "VARCHAR(255)",
    "TEXT",
    "BOOLEAN",
    "TIMESTAMP",
    "user_id"
  ],
  "tables": [
    [9, 0, 10],
    [9, 3, 11]
  ],
  "rels": [[0, 1, 2, -1, [1], [17]]],
  "joins": [],
  "path_map": [
    [0, 0],
    [1, 0]
  ],
  "cols": [
    [0, 1, 12, -1],
    [0, 2, 13, -1],
    [0, 6, 12, -1],
    [1, 4, 13, -1],
    [1, 5, 14, -1],
    [1, 7, 15, -1],
    [1, 8, 16, -1],
    [1, 17, 12, -1]
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
      'posts', COALESCE((
        SELECT json_agg(
          json_build_object(
            'title', t1.title,
            'content', t1.content
          )
          ORDER BY t1.created_at DESC
        )
        FROM "public"."posts" AS t1
        WHERE t1.user_id = t0.id
          AND t1.published = $1
        LIMIT $2
      ), '[]')
    )
    ORDER BY t0.name ASC
  ), '[]')
) AS result
FROM "public"."users" AS t0
WHERE t0.age > $3
LIMIT $4 OFFSET $5
```

## Parameters

```json
[true, 3, 21, 5, 10]
```

The SQL query returns data in the exact shape requested by the GraphQL query:

- Creates a JSON object with a "users" key at the top level
- Each user object contains "id", "name", and "posts" fields
- The "posts" field is a JSON array of post objects, each with "title" and "content" fields
- Applies filter conditions to both users (age > 21) and posts (published = true)
- Orders users by name ascending and posts by created_at descending
- Limits the users to 5 records with an offset of 10
- Limits the posts to 3 records per user
- Uses parameterized queries for all filter, limit, and offset values
- COALESCE ensures empty arrays instead of NULL values
