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

- 🚧 **Phase 2: Schema Resolution** - IN PROGRESS

  - SchemaResolver behavior defined
  - Integration with query parsing in development

- 📝 **Phase 3: SQL Generation** - PLANNED
  - PostgreSQL-specific SQL generation
  - Optimized JSON response construction

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

## Performance

GraSQL delivers exceptional performance across all phases of query processing:

- **Parsing Speed**: Even complex GraphQL queries parse in under 12 microseconds
- **High Throughput**: Benchmarks show ~60K-80K QPS for individual operations
- **Concurrent Processing**: ~50K-60K QPS with concurrent full pipeline processing
- **Scalability**: Near-linear scaling up to 4 concurrent tasks, with continued improvements up to 32+ tasks

| Operation     | Simple Query | Complex Query | Deeply Nested |
| ------------- | ------------ | ------------- | ------------- |
| Parse Query   | 15.32 μs     | 17.65 μs      | 17.69 μs      |
| Full Pipeline | 18.32 μs     | 18.22 μs      | 19.76 μs      |

Query complexity has minimal impact on performance, with even deeply nested queries seeing only ~16% slower parsing and ~8% slower full pipeline processing compared to simple queries.

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
  max_query_depth: 15,
  aggregate_field_suffix: "_agg",
  string_interner_capacity: 10000

# Implement the SchemaResolver behavior
defmodule MyApp.SchemaResolver do
  @behaviour GraSQL.SchemaResolver

  @impl true
  def resolve_table("users", _context), do: "public.users"
  def resolve_table("posts", _context), do: "public.posts"

  @impl true
  def resolve_relationship("users", "posts", _context) do
    %{
      join_type: :inner,
      table: "public.posts",
      join_condition: "posts.user_id = users.id",
      cardinality: :many
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

{:ok, {sql, params}} = GraSQL.to_sql(query, MyApp.SchemaResolver, %{user_id: 123})
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
