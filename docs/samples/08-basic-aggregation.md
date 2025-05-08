# GraphQL Sample 8: Basic Aggregation

This sample demonstrates a GraphQL query with a basic aggregation function.

## GraphQL Query

```graphql
{
  users_aggregate {
    aggregate {
      count
    }
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "6d9c2a8f3b5e7d1c",
  "strings": ["users_aggregate", "aggregate", "count"],
  "paths": [1, 0],
  "path_dir": [0],
  "path_types": [0],
  "cols": [],
  "ops": [[0, 0]]
}
```

- Note: The aggregation function is inferred from the field structure and doesn't require explicit column mapping.

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "6d9c2a8f3b5e7d1c",
  "strings": [
    "users_aggregate",
    "aggregate",
    "count",
    "public",
    "User",
    "INTEGER"
  ],
  "tables": [[3, 0, 4]],
  "rels": [],
  "joins": [],
  "path_map": [[0, 0]],
  "cols": [],
  "ops": [[0, 0]]
}
```

- The response includes the table information for the users table, even though no specific columns are requested.

## Expected SQL

```sql
SELECT json_build_object(
  'users_aggregate', json_build_object(
    'aggregate', json_build_object(
      'count', COUNT(*)
    )
  )
) AS result
FROM "public"."users" AS t0
WHERE (true)
```

## Parameters

```json
[]
```

The SQL query returns data in the exact shape requested by the GraphQL query:

- Creates a JSON object with a "users_aggregate" key at the top level
- Inside that, an "aggregate" object with a "count" property
- The COUNT(\*) function counts all rows in the users table
- Returns the exact hierarchical structure matching the GraphQL query
