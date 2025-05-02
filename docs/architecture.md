# GraSQL Architecture

## Introduction

GraSQL is a high-performance GraphQL to SQL compiler specifically optimized for PostgreSQL databases. It translates GraphQL queries into efficient SQL statements that leverage PostgreSQL's JSON functions to return structured data directly from the database, eliminating the need for additional processing in the application layer.

This document describes the architecture of GraSQL, including its major components, the transformation process, and key performance optimizations.

## Architecture Overview

GraSQL is composed of three main components:

1. **Parser**: Converts GraphQL query strings into an internal representation called Query Structure Tree (QST).
2. **Schema Resolver**: Enriches the QST with database metadata like fully qualified table names and relationship information.
3. **SQL Compiler**: Generates optimized SQL from the enriched QST, using PostgreSQL-specific features for maximum performance.

These components work together in a pipeline to transform GraphQL queries into highly efficient SQL statements.

## Workflow and Processing Phases

### Initialization

GraSQL automatically initializes at application startup through the GraSQL.Application module. Users can configure GraSQL through application environment variables in their config.exs file:

```elixir
config :grasql,
  query_cache_max_size: 2000,
  max_query_depth: 15,
  aggregate_field_suffix: "_agg"
```

Configuration options include:

- How to identify aggregate fields in GraphQL queries (e.g., fields ending with \_agg)
- How to identify single vs. many select/mutation operations
- Operator mappings (e.g., \_eq for =, \_gt for >, etc.)
- Join table handling preferences for many-to-many relationships

The application loads these settings during startup and initializes the GraSQL engine with the specified configuration.

### Processing Phases

GraSQL processes GraphQL queries in three distinct phases:

#### Phase 1: Query Scanning

The Query Scanning phase is optimized for high performance and minimal memory usage:

1. **Parsing**: A GraphQL query string is parsed using the `graphql-query` crate's arena-based allocator. This approach minimizes allocations and improves parsing performance.

2. **Field Path Extraction**: The parser extracts field paths that need resolution, including:

   - Fields from the selection sets (tree structure)
   - Fields from filter expressions (where clauses)

   This extraction process uses a single-pass visitor pattern to efficiently traverse the AST.

3. **String Interning**: Field names are interned to optimize memory usage and comparison operations. Each unique string is stored only once in a global table, and integer IDs are used throughout the system to reference these strings.

4. **Deduplication**: Field paths are stored in a HashSet to automatically eliminate duplicates, ensuring each field path is only resolved once.

5. **Cache Management**: The parsed query is stored in a thread-safe cache using xxHash (an extremely fast hashing algorithm) for query ID generation. This enables efficient reuse of the parsed AST in Phase 3.

6. **Memory Optimization**: Several techniques are used to minimize memory usage:

   - SmallVec for field paths that are typically short (<8 elements)
   - Arena allocation for AST nodes
   - Structural sharing for common path prefixes
   - Minimal data structures crossing the NIF boundary

7. **NIF Interface**: The parser returns a minimal resolution request to Elixir, containing only the field names and unique field paths that need resolution. This minimizes data transfer across the NIF boundary.

The output of Phase 1 includes:

- A query ID that can be used to retrieve the cached AST in Phase 3
- A minimal resolution request containing only the field names and paths that need to be resolved

#### Phase 2: Schema Resolution

- Elixir code processes the resolution request using user-implemented resolvers
- Resolver maps GraphQL fields to database tables and relationships
- Resolver adds fully qualified table names, join conditions, etc.
- Outputs: Resolved Information

#### Phase 3: SQL Generation

- Elixir calls back to the SQL Compiler NIF with the query ID, resolved information, and variables
- Compiler retrieves the cached parsed query using the query ID
- Compiler builds a complete QST using the parsed query and resolved information
- Compiler generates optimized PostgreSQL SQL with parameterized queries
- Compiler removes the parsed query from the cache to free memory
- Outputs: SQL string + parameters

This approach eliminates the need to parse the GraphQL query twice, significantly improving performance for complex queries.

## Query Structure Tree (QST)

The QST is the internal representation of a GraphQL query used throughout GraSQL. It serves as an intermediate representation that bridges GraphQL and SQL concepts.

### Key Elements of the QST

- **Operation Type**: Query or Mutation (Subscription not supported)
- **Root Fields**: Top-level fields in the query, mapped to tables
- **Selection Sets**: Fields selected at each level
- **Arguments**: Field arguments like filters, pagination, and sorting
- **Variables**: Variable definitions and usages
- **Relationships**: Nested field relationships
- **Aggregations**: Aggregation operations like count, sum, etc.

### Example QST Structure (Simplified)

```json
{
  "operation_type": "query",
  "root_fields": [
    {
      "name": "users",
      "alias": "active_users",
      "table": null, // Filled by Schema Resolver
      "selection_set": [
        { "name": "id" },
        { "name": "name" },
        {
          "name": "posts",
          "relationship": { "type": "one_to_many" },
          "table": null, // Filled by Schema Resolver
          "selection_set": [{ "name": "title" }, { "name": "content" }],
          "arguments": {
            "where": { "published": { "_eq": true } },
            "order_by": { "created_at": "desc" },
            "limit": 5
          }
        }
      ],
      "arguments": {
        "where": { "status": { "_eq": "active" } }
      }
    }
  ],
  "variables": {}
}
```

## Parser Component

The Parser is responsible for scanning GraphQL query strings to identify what needs resolution, and for caching the parsed query for later use in SQL generation.

### Parser Responsibilities

1. Parse and validate GraphQL syntax
2. Extract fields and relationships that need resolution
3. Cache the parsed query for reuse in Phase 3
4. Generate a unique query ID to reference the cached query
5. Identify operation type (query/mutation)
6. Handle variables and their types

### Query Caching

To avoid parsing the GraphQL query twice, the Parser implements an internal caching mechanism:

1. After parsing a query, the Parser stores the parsed AST in a process-wide thread-safe cache
2. The cache is keyed by a unique query ID (hash of the query string)
3. The query ID is returned to Elixir and passed back in Phase 3
4. In Phase 3, the SQL Compiler retrieves the parsed query from the cache
5. After SQL generation, the parsed query is removed from the cache

The cache is implemented as a global concurrent hash map (using libraries like `dashmap`), ensuring that:

- Cached queries are accessible from any scheduler thread/CPU core
- Access is thread-safe without significant contention
- Memory usage is managed through automatic cleanup

In multi-core environments, where Phase 1 and Phase 3 might execute on different CPU cores, this shared cache ensures the parsed query remains accessible. If a cache miss occurs (which is rare but possible), the system transparently falls back to reparsing the query, ensuring robustness without compromising the API.

### Parser Limitations

- Does not support GraphQL Fragments
- Does not support GraphQL Directives
- Does not support GraphQL Subscriptions

## Schema Resolver Component

The Schema Resolver connects the abstract GraphQL schema to concrete database tables and relationships. It's implemented by library users to provide database-specific metadata.

### Schema Resolver Behavior

The Schema Resolver is an Elixir behavior that must be implemented by users of the library. It includes:

1. `resolve_table/2`: Maps a GraphQL type to a fully qualified database table
2. `resolve_relationship/2`: Maps a nested field to a table relationship

### Context Passing

The Schema Resolver receives a context map which can contain:

- Tenant ID
- User ID
- User roles
- Any other application-specific data

This context is passed unchanged to user-implemented resolvers, allowing for access control and multi-tenancy.

## SQL Compiler Component

The SQL Compiler generates optimized PostgreSQL SQL from the enriched QST and variables. It's the most complex component and incorporates several optimization techniques.

### SQL Generation Techniques

1. **JSON Construction**:

   - Uses PostgreSQL's JSON functions (`json_build_object`, `json_agg`, `row_to_json`) for direct response construction
   - Uses `coalesce` with empty arrays to handle null results (e.g., `coalesce(json_agg(...), '[]')`)
   - Builds nested JSON structures that exactly match the GraphQL response shape

2. **Nested Queries**:

   - Uses LATERAL JOINs for efficient nested data fetching
   - Properly handles one-to-many and many-to-many relationships
   - Constructs nested objects using subqueries and JSON aggregation
   - Uses table aliases with a clear, hierarchical naming convention

3. **Filtering**:

   - Translates GraphQL arguments to WHERE clauses with proper operator mapping (e.g., `_eq` → `=`, `_ilike` → `ILIKE`)
   - Supports complex logical operations (AND, OR, NOT)
   - Handles nested filters on relationships using EXISTS subqueries
   - Supports filtering on deeply nested relationships (e.g., users → roles → application → name)
   - Applies proper type casting where needed (e.g., `('value') :: text`)

4. **Aggregations**:

   - Generates efficient aggregation queries (COUNT, SUM, AVG, etc.)
   - Supports aggregation options like DISTINCT and column selection
   - Returns aggregation results alongside entity data in a single query
   - Creates properly structured JSON objects for aggregate results

5. **Pagination and Sorting**:

   - Implements offset/limit pagination at any nesting level
   - Applies LIMIT and OFFSET clauses to the appropriate subqueries
   - Supports multi-field sorting with direction control
   - Preserves pagination parameters through parameterization

6. **Parameterization**:
   - All user inputs are properly parameterized to prevent SQL injection
   - Extracts inline values to parameters for better query caching
   - Handles complex variable types including arrays and objects

### SQL Output Structure

The SQL generated for a GraphQL query with nested relationships and aggregations typically follows this pattern:

```sql
SELECT
  json_build_object(
    'data', json_build_object(
      'root_field', coalesce(json_agg(
        row_to_json(q0)
      ), '[]')
    )
  ) AS result
FROM (
  -- Main query with filters
  SELECT
    t0.id,
    t0.name,
    (
      -- Relationship subquery using LATERAL JOIN
      SELECT coalesce(json_agg(
        row_to_json(q1)
      ), '[]') AS related_items
      FROM (
        SELECT
          t1.id,
          t1.title,
          -- Potentially more nested relationships
          (
            SELECT json_build_object(
              'aggregate', json_build_object(
                'count', COUNT(*)
              )
            )
            FROM related_table t2
            WHERE t2.parent_id = t1.id
          ) AS aggregation
        FROM related_table t1
        WHERE t1.parent_id = t0.id
        ORDER BY t1.created_at DESC
        LIMIT $1 OFFSET $2
      ) q1
    ) AS relationship
  FROM base_table t0
  WHERE
    -- Simple filter
    t0.status = $3
    -- Complex relationship filter
    AND EXISTS (
      SELECT 1
      FROM join_table j0
      JOIN other_table o0 ON j0.other_id = o0.id
      WHERE
        j0.base_id = t0.id
        AND o0.property = $4
    )
) q0
```

This structure:

1. Returns the complete response directly from PostgreSQL as a JSON object
2. Exactly matches the shape of the expected GraphQL response
3. Uses a consistent, intuitive naming convention for table aliases (t0, t1, etc. for tables; q0, q1, etc. for subqueries)
4. Handles empty results with coalesce to ensure consistent response format
5. Places filter conditions at the appropriate query level
6. Uses parameterization ($1, $2, etc.) for all variable inputs

## Implementation Optimizations

GraSQL's Rust components employ several optimization techniques to ensure maximum performance:

1. **String Interning**: Identical string values (like field names, operators, etc.) are stored only once and referenced multiple times, reducing memory usage and improving string comparison performance.

2. **Copy-on-Write (COW)**: Data structures use COW semantics where appropriate to avoid unnecessary cloning, allowing efficient sharing of data while maintaining immutability.

3. **Arena Allocation**: Related objects that have the same lifetime are allocated together in memory arenas, reducing allocation overhead and improving cache locality.

4. **SmallVec**: Collections expected to contain few elements use stack allocation via `SmallVec` instead of heap allocation, eliminating allocation overhead for common cases.

5. **Function Inlining**: Critical functions are marked for inlining, eliminating function call overhead in performance-sensitive code paths. Since binary size is not a primary concern for server-side applications, GraSQL prioritizes runtime performance through aggressive inlining.

These low-level optimizations significantly improve parsing speed, memory efficiency, and SQL generation performance, especially for complex queries with deep nesting and numerous fields.

## Performance Considerations

GraSQL focuses on performance in several key ways:

### 1. Eliminating the N+1 Query Problem

By generating SQL that returns complete nested structures with LATERAL JOINs, GraSQL eliminates the N+1 query problem common in many GraphQL implementations. A single SQL query can fetch an entire graph of related data.

### 2. Leveraging PostgreSQL's JSON Capabilities

Instead of fetching raw data and constructing the response in application code, GraSQL pushes this work to PostgreSQL using its native JSON functions. This:

- Reduces network traffic by sending only the final JSON result
- Eliminates serialization/deserialization overhead
- Takes advantage of PostgreSQL's internal optimization capabilities

### 3. Strategic Use of EXISTS Subqueries

For relationship filtering, GraSQL uses EXISTS subqueries which are often more efficient than JOINs for filtering purposes, especially when:

- Only checking for existence of related records
- Filtering through multiple levels of relationships
- Working with complex filtering conditions

### 4. Query Parameterization and Plan Caching

Parameterized queries allow PostgreSQL to cache execution plans, dramatically improving performance for repeated queries with different variables. GraSQL ensures that:

- All user inputs are properly parameterized
- Constants and literal values are extracted as parameters when beneficial
- Query structure remains stable across executions with different inputs

### 5. Single-Round-Trip Architecture

The entire JSON response is constructed and returned in a single database query, eliminating multiple round-trips between the application and database, which is especially important for high-latency connections.

### 6. Optimized Data Loading

GraSQL generates SQL that:

- Only selects the fields requested in the GraphQL query
- Applies filtering as early as possible in the query execution
- Uses appropriate join types based on relationship cardinality
- Handles pagination at the database level to limit result size

### 7. Query Parsing Optimization

GraSQL implements a parse-once strategy to avoid the computational cost of parsing complex GraphQL queries multiple times:

- Parsed queries are cached after Phase 1
- The cached representation is reused in Phase 3
- This eliminates redundant parsing work, particularly beneficial for large and complex queries
- Internal cache management ensures memory efficiency

## Conclusion

GraSQL's architecture is designed for high performance and flexibility. By decomposing the problem into distinct phases (parsing, schema resolution, and SQL generation), it provides a clean separation of concerns that makes the library both powerful and adaptable.

The focus on generating optimized PostgreSQL-specific SQL that returns complete JSON responses directly from the database distinguishes GraSQL from other GraphQL implementations and allows it to achieve exceptional performance.
