# GraphQL Sample 13: Many-to-Many Relationship

This sample demonstrates a GraphQL query with a many-to-many relationship using a join table.

## GraphQL Query

```graphql
{
  users {
    id
    name
    categories {
      name
    }
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "8d2e6f4a9c1b3d5e",
  "strings": ["users", "id", "name", "categories", "name"],
  "paths": [1, 0, 2, 0, 3],
  "path_dir": [0, 2],
  "path_types": [0, 1],
  "cols": [
    [0, [1, 2]],
    [3, [4]]
  ],
  "ops": [[0, 0]]
}
```

- The path structure includes the users table and the categories relationship.

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "8d2e6f4a9c1b3d5e",
  "strings": [
    "users",
    "id",
    "name",
    "categories",
    "name",
    "public",
    "User",
    "Category",
    "user_categories",
    "INTEGER",
    "VARCHAR(255)",
    "user_id",
    "category_id"
  ],
  "tables": [
    [5, 0, 6],
    [5, 3, 7],
    [5, 8, -1]
  ],
  "rels": [[0, 1, 3, 2, [1], [12, 11]]],
  "joins": [[2, [11, 12], [0, 1], [1, 2]]],
  "path_map": [
    [0, 0],
    [1, 0]
  ],
  "cols": [
    [0, 1, 9, -1],
    [0, 2, 10, -1],
    [1, 4, 10, -1],
    [2, 11, 9, -1],
    [2, 12, 9, -1]
  ],
  "ops": [[0, 0]]
}
```

- Tables include users, categories, and the join table user_categories
- The relationship is defined as many-to-many (type 3) with join table information
- The joins section contains the mapping between tables and their join columns

## Expected SQL

```sql
SELECT json_build_object(
  'users', COALESCE(json_agg(
    json_build_object(
      'id', t0.id,
      'name', t0.name,
      'categories', COALESCE((
        SELECT json_agg(
          json_build_object(
            'name', t1.name
          )
        )
        FROM "public"."user_categories" AS t2
        JOIN "public"."categories" AS t1 ON t2.category_id = t1.id
        WHERE t2.user_id = t0.id
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
- Each user object contains "id", "name", and "categories" fields
- The "categories" field is a JSON array of category objects, each with a "name" field
- Uses a correlated subquery with JOIN to handle the many-to-many relationship
- The join table (user_categories) connects users and categories tables
- COALESCE ensures empty arrays instead of NULL values for users with no categories
