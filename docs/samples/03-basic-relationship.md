# GraphQL Sample 3: Basic Relationship

This sample demonstrates a GraphQL query with a one-to-many relationship.

## GraphQL Query

```graphql
{
  users {
    id
    posts {
      title
    }
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "5e9a2c7b1d8f6e3a",
  "strings": ["users", "id", "posts", "title"],
  "paths": [1, 0, 2, 0, 2],
  "path_dir": [0, 2],
  "path_types": [0, 1],
  "cols": [
    [0, [1]],
    [2, [3]]
  ],
  "ops": [[0, 0]]
}
```

- `paths`: Contains two paths: [users] and [users, posts]
- `path_dir`: Points to where each path starts in the paths array
- `path_types`: [0] for table, [1] for relationship
- `cols`: Maps columns for each table: user.id and posts.title

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "5e9a2c7b1d8f6e3a",
  "strings": [
    "users",
    "id",
    "posts",
    "title",
    "public",
    "User",
    "Post",
    "INTEGER",
    "VARCHAR(255)",
    "user_id"
  ],
  "tables": [
    [4, 0, 5],
    [4, 2, 6]
  ],
  "rels": [[0, 1, 2, -1, [1], [9]]],
  "joins": [],
  "path_map": [
    [0, 0],
    [1, 0]
  ],
  "cols": [
    [0, 1, 7, -1],
    [1, 3, 8, -1],
    [1, 9, 7, -1]
  ],
  "ops": [[0, 0]]
}
```

- `tables`: Two tables: [public, users, User] and [public, posts, Post]
- `rels`: One relationship (has_many, type=2) from users to posts with foreign key user_id
- `path_map`: Maps path_id 0 to the users table and path_id 1 to the relationship
- `cols`: Column definitions for id, title, and user_id with their SQL types

## Expected SQL

```sql
SELECT json_build_object(
  'users', COALESCE(json_agg(
    json_build_object(
      'id', t0.id,
      'posts', COALESCE((
        SELECT json_agg(
          json_build_object(
            'title', t1.title
          )
        )
        FROM "public"."posts" AS t1
        WHERE t1.user_id = t0.id
      ), '[]')
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
- Each user object contains "id" and "posts" fields
- The "posts" field is a JSON array of post objects, each with a "title" field
- Uses nested COALESCE functions to ensure empty arrays instead of NULL values
