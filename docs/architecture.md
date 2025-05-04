# GraSQL Architecture

This document outlines the architecture of GraSQL, a high-performance GraphQL to SQL compiler written in Elixir with Rust NIFs for performance-critical operations.

## Overview

GraSQL transforms GraphQL queries into efficient PostgreSQL SQL with a focus on extreme performance (100K+ QPS). It follows a modular architecture with three distinct phases:

1. **Query Scanning**: Parses and extracts information from GraphQL queries
2. **Schema Resolution**: Resolves GraphQL fields to database tables and relationships
3. **SQL Generation**: Generates optimized SQL from the parsed query and resolved schema

Each phase is designed for maximum performance and minimal data transfer between Elixir and Rust.

## Processing Pipeline

```
┌───────────────┐     ┌───────────────────┐     ┌───────────────┐     ┌────────────────┐
│  GraphQL      │     │  Parse Query      │     │  Resolve      │     │  Generate SQL  │
│  Query        │────▶│  (Rust NIF)       │────▶│  Schema       │────▶│  (In Progress) │
│               │     │                   │     │  (Elixir)     │     │                │
└───────────────┘     └───────────────────┘     └───────────────┘     └────────────────┘
                              │                         │
                              ▼                         ▼
                      ┌───────────────────┐     ┌───────────────┐
                      │  Query Cache      │     │  Schema Cache │
                      │  (Rust - Moka)    │     │  (Elixir)     │
                      └───────────────────┘     └───────────────┘
```

## Phase 1: Query Scanning (COMPLETE)

The first phase of processing is handled by Rust NIFs for maximum performance. It includes:

### GraphQL Parser

- **Purpose**: Converts a GraphQL query string into an AST
- **Implementation**: Custom Rust parser with SIMD optimization where possible
- **Optimizations**:
  - String interning with `lasso::Rodeo` for memory efficiency
  - SmallVec for field paths to avoid heap allocations
  - Aggressive function inlining with `#[inline(always)]`
  - Arena allocation with `bumpalo` for related objects
  - Minimal AST representation focused on SQL generation needs

### Field Path Extraction

- **Purpose**: Extracts field paths for schema resolution
- **Implementation**: AST visitor pattern in Rust
- **Optimizations**:
  - Single-pass traversal to extract all relevant information
  - SmallVec to avoid heap allocations for typical field paths
  - Efficient string representation with integer IDs (interning)

### Query Caching

- **Purpose**: Avoids repeated parsing of identical queries
- **Implementation**: Thread-safe LRU cache with TTL
- **Technology**: `moka` crate for concurrent caching
- **Features**:
  - Time-based eviction (configurable TTL)
  - Size-based eviction (configurable max size)
  - Thread-safe for concurrent access
  - Fast lookup with xxHash3 for query IDs

## Phase 2: Schema Resolution (COMPLETE)

The second phase maps GraphQL fields to database tables and relationships:

### Schema Resolver

- **Purpose**: Resolves GraphQL fields to database tables and relationships
- **Implementation**: Elixir with SchemaResolver behavior
- **Features**:
  - Custom resolver integration via behavior
  - Context passing for multi-tenancy support
  - Comprehensive domain model for SQL generation
  - Parallel processing with Task.async_stream

### Parallel Processing

- **Purpose**: Maximize throughput on multi-core systems
- **Implementation**: Task.async_stream with dynamic concurrency
- **Optimizations**:
  - Uses System.schedulers_online() to determine optimal concurrency
  - Batches relationship resolution by depth level
  - Minimizes IPC overhead by resolving related entities together

### Path Mapping

- **Purpose**: Efficient O(1) lookups during SQL generation
- **Implementation**: Map-based path lookups
- **Features**:
  - Fast field path to table/relationship lookup
  - Compact representation for memory efficiency
  - Optimized for SQL generation phase access patterns

## Phase 3: SQL Generation (PLANNED)

The final phase generates optimized SQL from the parsed query and resolved schema:

### SQL Generator

- **Purpose**: Transforms GraphQL AST and schema into efficient SQL
- **Implementation**: SQL DSL with PostgreSQL optimizations
- **Features**:
  - JSON aggregation for nested relationships
  - Parameterized queries for security
  - Optimized join ordering
  - Advanced filtering and sorting
  - Pagination support

### JSON Response Construction

- **Purpose**: Builds JSON directly in PostgreSQL
- **Implementation**: JSON functions in generated SQL
- **Features**:
  - Minimizes application-level processing
  - Returns complete response structure from database
  - Handles nested relationships efficiently

## Performance Considerations

GraSQL is designed for extreme performance with a target of 100K+ QPS. Key performance optimizations include:

### Rust NIF Implementation

- Critical performance paths implemented in Rust
- Minimal data transfer across NIF boundary
- Use of SIMD instructions where applicable
- Zero-copy parsing where possible

### Memory Efficiency

- String interning to avoid duplicate strings
- SmallVec for short arrays to avoid heap allocations
- Arena allocation for related objects
- Minimal intermediate representations

### Concurrency

- Thread-safe caching with sharded concurrent maps
- Parallel schema resolution to utilize all CPU cores
- Lock-free algorithms where possible
- Efficient handling of contended resources

### Database Optimizations

- SQL generation optimized for PostgreSQL's query planner
- Use of WITH clauses for complex queries
- Efficient JSON construction with jsonb_agg and jsonb_build_object
- Parameterized queries to leverage prepared statement caching

## Benchmark Results

GraSQL achieves impressive performance numbers:

| Operation     | Simple Query | Complex Query | Deeply Nested |
| ------------- | ------------ | ------------- | ------------- |
| Parse Query   | 16.30 μs     | 18.64 μs      | 18.80 μs      |
| Full Pipeline | 18.31 μs     | 18.46 μs      | 20.99 μs      |

In concurrent benchmarks, GraSQL shows near-linear scaling up to 4 concurrent tasks and continues to improve up to 32+ tasks, achieving approximately 70K+ QPS with complex queries.

## Frontend Architecture

The primary interface to GraSQL is the `GraSQL` module with three main functions:

- `parse_query/1`: Parses a GraphQL query and returns field paths
- `resolve_schema/3`: Resolves GraphQL fields to database schema
- `generate_sql/3`: Generates SQL from the parsed query and resolved schema

## Security Considerations

Security is a key focus in GraSQL:

- Parameterized queries to prevent SQL injection
- Configurable maximum query depth to prevent DoS attacks
- Query timeout settings
- Rate limiting integration

## Future Work

Beyond the current roadmap, future work may include:

- Support for additional database backends
- Subscription support via PostgreSQL LISTEN/NOTIFY
- Schema introspection for auto-generating resolvers
- Integration with GraphQL federation
- Advanced caching strategies

## References

- [PostgreSQL JSON Functions](https://www.postgresql.org/docs/current/functions-json.html)
- [Rust Performance Techniques](https://nnethercote.github.io/perf-book/)
- [Safe Elixir NIFs with Rustler](https://hexdocs.pm/rustler)
