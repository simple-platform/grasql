# GraphQL Sample 9: Aggregation with Nodes

This sample demonstrates a GraphQL query with both aggregation functions and regular field selection.

## GraphQL Query

```graphql
{
  users_aggregate {
    aggregate {
      count
      max {
        id
      }
    }
    nodes {
      name
    }
  }
}
```

## ResolutionRequest

This is the request sent from Phase 1 (Query Scanning) to Phase 2 (Schema Resolution):

```json
{
  "query_id": "3e5c9a7d2b4f1e8c",
  "strings": [
    "users_aggregate",
    "aggregate",
    "count",
    "max",
    "id",
    "nodes",
    "name"
  ],
  "paths": [1, 0],
  "path_dir": [0],
  "path_types": [0],
  "cols": [[0, [6]]],
  "ops": [[0, 0]]
}
```

- The aggregation functions (count, max) are recognized but not included in columns since they don't need resolution.
- Only the "name" field is included in columns since it's a regular field selection in the "nodes" section.

## ResolutionResponse

This is the response from Phase 2 (Schema Resolution) to Phase 3 (SQL Generation):

```json
{
  "query_id": "3e5c9a7d2b4f1e8c",
  "strings": [
    "users_aggregate",
    "aggregate",
    "count",
    "max",
    "id",
    "nodes",
    "name",
    "public",
    "User",
    "INTEGER",
    "VARCHAR(255)"
  ],
  "tables": [[7, 0, 8]],
  "rels": [],
  "joins": [],
  "path_map": [[0, 0]],
  "cols": [
    [0, 4, 9, -1],
    [0, 6, 10, -1]
  ],
  "ops": [[0, 0]]
}
```

- The response includes information for both the aggregate functions and the requested columns.

## Expected SQL

```sql
WITH aggregation AS (
  SELECT
    COUNT(*) as count,
    MAX(t0.id) as max_id,
    json_agg(
      json_build_object(
        'name', t0.name
      )
    ) as nodes
  FROM "public"."users" AS t0
  WHERE (true)
)
SELECT json_build_object(
  'users_aggregate', json_build_object(
    'aggregate', json_build_object(
      'count', aggregation.count,
      'max', json_build_object(
        'id', aggregation.max_id
      )
    ),
    'nodes', COALESCE(aggregation.nodes, '[]')
  )
) AS result
FROM aggregation
```

## Parameters

```json
[]
```

The SQL query returns data in the exact shape requested by the GraphQL query:

- Uses a CTE (WITH clause) to calculate all aggregations in a single pass over the data
- Creates a JSON object with the exact structure requested in the GraphQL query
- The "users_aggregate" object contains both "aggregate" and "nodes" properties
- The "aggregate" object contains "count" and "max" properties, with "max" being an object with an "id" property
- The "nodes" property is an array of objects with "name" properties
- COALESCE ensures "nodes" is an empty array rather than NULL if no records are found
