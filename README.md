# GraSQL

[![Package Version](https://img.shields.io/hexpm/v/grasql)](https://hex.pm/packages/grasql)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/grasql/)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)

A high-performance GraphQL to SQL compiler written in Elixir with Rust NIFs for performance-critical operations. GraSQL aims to transform GraphQL queries into efficient PostgreSQL SQL with a focus on extreme performance (100K+ QPS).

## Status

GraSQL is in active development and follows a phased approach:

- ✅ **Phase 1: Query Scanning** - COMPLETE

  - High-performance GraphQL parser integrated
  - Field path extraction to minimize resolution work
  - Query caching for reuse during SQL generation
  - Advanced performance optimizations (string interning, smallvec, etc.)
  - Comprehensive test coverage including property-based testing

- ✅ **Phase 2: Schema Resolution** - COMPLETE

  - SchemaResolver behavior defined and implemented
  - Parallel processing of tables and relationships
  - Efficient path mapping for O(1) lookups
  - Context passing for multi-tenancy support
  - Integration with query parsing completed

- 📝 **Phase 3: SQL Generation** - PLANNED
  - PostgreSQL-specific SQL generation
  - Optimized JSON response construction
  - Parameterized queries for security
  - Advanced filtering, pagination, and sorting
  - Support for aggregations and nested queries

## Overview

GraSQL translates GraphQL queries into efficient PostgreSQL SQL that leverages JSON functions to return structured data directly from the database. This approach eliminates the N+1 query problem and reduces the load on application servers by pushing response construction to the database.

### Key Features

- **Extreme Performance**: Built for 100K+ QPS through careful optimization
- **Memory Efficiency**: Minimizes allocations with arena patterns, string interning, and smallvec optimizations
- **Minimal Data Transfer**: Only essential data crosses the NIF boundary between Elixir and Rust
- **JSON Direct from PostgreSQL**: Generates SQL that returns complete JSON structures
- **Field-Level Filtering**: Supports complex filtering expressions
- **Pagination & Sorting**: Built-in support at any nesting level
- **Relationship Handling**: Efficiently handles one-to-many and many-to-many relationships
- **Aggregations**: Supports aggregation alongside regular queries
- **Parallel Processing**: Resolves schema information concurrently for maximum throughput

## Performance

GraSQL delivers exceptional performance across all phases of query processing:

- **Parsing Speed**: Even complex GraphQL queries parse in under 12 microseconds
- **High Throughput**: Benchmarks show ~50K-60K QPS for individual operations
- **Concurrent Processing**: ~70K+ QPS with concurrent full pipeline processing (32 threads)
- **Scalability**: Near-linear scaling up to 4 concurrent tasks, with continued improvements up to 32+ tasks
- **Parallel Schema Resolution**: Resolves tables and relationships concurrently using all available CPU cores

| Operation     | Simple Query | Complex Query | Deeply Nested |
| ------------- | ------------ | ------------- | ------------- |
| Parse Query   | 16.30 μs     | 18.64 μs      | 18.80 μs      |
| Full Pipeline | 18.31 μs     | 18.46 μs      | 20.99 μs      |

Query complexity has minimal impact on performance, with even deeply nested queries seeing only ~15% slower parsing and ~15% slower full pipeline processing compared to simple queries.

In production environments with optimized configurations and multi-instance deployments, GraSQL can easily scale to hundreds of thousands of QPS, meeting its design target of 100,000+ QPS.

For detailed benchmark methodology and results, see the [benchmarks.md](docs/benchmarks.md) file.

## Performance Optimizations

GraSQL employs several key optimizations to achieve its performance goals:

- **String Interning**: Using the `lasso` crate to store each unique string only once, referenced by integer IDs
- **SmallVec**: Stack allocation for field paths to avoid heap allocations for typical paths (<8 segments)
- **Aggressive Function Inlining**: All critical functions marked with `#[inline(always)]` to eliminate call overhead
- **Thread-safe Caching**: Using `moka` and `dashmap` for efficient concurrent caching with TTL and LRU eviction
- **Efficient Hashing**: xxHash3 for ultra-fast query ID generation
- **Arena Allocation**: Using `bumpalo` for allocating related objects together in memory
- **Minimal NIF Boundary**: Only essential data crosses between Elixir and Rust, with optimized encoding/decoding
- **Parallel Processing**: Schema resolution uses Task.async_stream with dynamic concurrency based on available cores

## Installation

Add `grasql` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:grasql, "~> 0.1.0"}
  ]
end
```

## Basic Usage

```elixir
# Configure GraSQL in your application
config :grasql,
  query_cache_max_size: 2000,
  query_cache_ttl_seconds: 600,
  max_query_depth: 15,
  aggregate_field_suffix: "_agg",
  string_interner_capacity: 10_000,
  schema_resolver: MyApp.SchemaResolver

# Implement the SchemaResolver behavior
defmodule MyApp.SchemaResolver do
  use GraSQL.SchemaResolver

  @impl true
  def resolve_table("users", _context) do
    %GraSQL.Schema.Table{schema: "public", name: "users"}
  end

  @impl true
  def resolve_relationship("posts", parent_table, _context) do
    %GraSQL.Schema.Relationship{
      type: :has_many,
      source_table: parent_table,
      target_table: %GraSQL.Schema.Table{schema: "public", name: "posts"},
      source_columns: ["id"],
      target_columns: ["user_id"],
      join_table: nil
    }
  end

  def resolve_relationship("categories", %{name: "posts"} = parent_table, _context) do
    %GraSQL.Schema.Relationship{
      type: :many_to_many,
      source_table: parent_table,
      target_table: %GraSQL.Schema.Table{schema: "public", name: "categories"},
      source_columns: ["id"],
      target_columns: ["id"],
      join_table: %GraSQL.Schema.JoinTable{
        schema: "public",
        name: "post_categories",
        source_columns: ["post_id"],
        target_columns: ["category_id"]
      }
    }
  end
end

# Use GraSQL to convert GraphQL to SQL
query = """
query {
  users(where: { active: { _eq: true } }) {
    id
    name
    posts {
      title
      content
    }
  }
}
"""

{:ok, sql, params} = GraSQL.generate_sql(query, %{user_id: 123})

# Execute the SQL with your database library
MyApp.Repo.query!(sql, params)
```

## Documentation

Detailed documentation including architecture, design choices, and advanced usage is available at [hexdocs.pm/grasql](https://hexdocs.pm/grasql/).

## Benchmarks

GraSQL includes comprehensive benchmarks in the `bench` directory:

```bash
# Run the parser benchmarks
cd native/grasql
cargo bench

# Run the Elixir benchmarks
mix bench
```

## License

GraSQL is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
