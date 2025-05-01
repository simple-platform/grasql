# GraSQL

[![Package Version](https://img.shields.io/hexpm/v/grasql)](https://hex.pm/packages/grasql)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/grasql/)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)

A GraphQL to SQL compiler written in Elixir with Rust NIFs for performance-critical operations. GraSQL aims to generate efficient SQL directly from GraphQL queries.

## Project Status

**Early Development**: GraSQL is currently in early development. Core components like GraphQL parsing and query caching are functional, but the full GraphQL to SQL transformation is still being implemented.

## Overview

GraSQL aims to transform GraphQL queries into optimized SQL statements. The project uses a resolver approach for schema mapping, making it adaptable to different database schemas and authorization requirements.

## Current Features

- **GraphQL Query Parsing**:
  - Fast parsing of GraphQL queries using Rust
  - Extraction of operation kind and operation name
  - Performance-optimized implementation
- **Efficient Query Caching**:
  - xxHash-based caching of parsed queries
  - Configurable cache size and TTL
  - Automatic LRU eviction
- **Flexible Configuration**:
  - Naming conventions for fields and parameters
  - Operator mappings between GraphQL and SQL
  - Cache settings for optimization
  - Performance limits to prevent resource exhaustion
- **Schema Resolver Framework**:
  - Behavior definition for database schema mapping
  - Interface for resolving tables and relationships

## Planned Features

- **Complete SQL Generation**:
  - Generation of optimized SQL from GraphQL queries
  - Support for nested relationships
  - Field selection based on GraphQL query structure
- **Query Capabilities**:
  - Filtering at root and nested levels
  - Sorting and pagination
  - Aggregation functions
- **Security Features**:
  - Fully parameterized queries
  - Context-aware resolvers for authorization

## Installation

Add GraSQL to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:grasql, "~> 0.1.0"}
  ]
end
```

Then run:

```shell
mix deps.get
```

## Configuration

GraSQL is automatically initialized at application startup and can be configured through application environment variables:

```elixir
# In config/config.exs
config :grasql,
  query_cache_max_size: 2000,
  max_query_depth: 15,
  schema_resolver: MyApp.SchemaResolver
```

Available configuration options:

| Option                      | Description                                             | Default                 |
| --------------------------- | ------------------------------------------------------- | ----------------------- |
| `query_cache_max_size`      | Maximum number of entries in the query cache            | 1000                    |
| `query_cache_ttl_seconds`   | Time-to-live for cache entries in seconds               | 3600                    |
| `max_query_depth`           | Maximum allowed depth for GraphQL queries               | 10                      |
| `aggregate_field_suffix`    | Suffix for aggregate field names                        | "\_agg"                 |
| `primary_key_argument_name` | Parameter name for primary key in single entity queries | "id"                    |
| `operators`                 | Map of GraphQL operator suffixes                        | See `GraSQL.Config`     |
| `schema_resolver`           | Module implementing the SchemaResolver behavior         | `GraSQL.SimpleResolver` |

See `GraSQL.Config` module documentation for all available configuration options.

## Basic Usage

### 1. Define a Schema Resolver

```elixir
defmodule MyApp.SchemaResolver do
  @behaviour GraSQL.SchemaResolver

  @impl true
  def resolve_table(table, _ctx) do
    # Add database schema information
    Map.merge(table, %{
      schema: "public",
      columns: ["id", "name", "email"],
      primary_key: ["id"]
    })
  end

  @impl true
  def resolve_relationship(relationship, _ctx) do
    # Define relationship between tables
    Map.merge(relationship, %{
      join_type: :left_outer,
      join_conditions: [{"users.id", "posts.user_id"}]
    })
  end
end
```

### 2. Configure the Resolver

```elixir
# In config/config.exs
config :grasql,
  schema_resolver: MyApp.SchemaResolver
```

### 3. Parse and Process a GraphQL Query

```elixir
query = """
{
  users {
    id
    name
  }
}
"""

# Parse the query
case GraSQL.parse_query(query) do
  {:ok, query_id, operation_kind, operation_name} ->
    IO.puts("Parsed query with ID: #{query_id}")

    # Generate SQL (note: SQL generation is limited in current implementation)
    case GraSQL.generate_sql(query, %{}) do
      {:ok, sql, params} ->
        # Execute the SQL with your database client
        IO.puts("Generated SQL: #{sql}")

      {:error, reason} ->
        # Handle error
        IO.puts("Failed to generate SQL: #{reason}")
    end

  {:error, reason} ->
    # Handle error
    IO.puts("Failed to parse query: #{reason}")
end
```

Note: The SQL generation functionality is in early development and currently returns basic placeholder SQL.

## Development Status and Roadmap

GraSQL is being actively developed with the following priorities:

1. **Current Status**: Basic GraphQL parsing, caching, and configuration system are implemented.
2. **Short-term Goals**: Complete SQL generation for simple queries.
3. **Medium-term Goals**: Support for filters, sorting, and nested relationships.
4. **Long-term Goals**: Full feature parity with the planned feature set.

## Benchmarks

GraSQL includes benchmarks for GraphQL parsing and query hashing performance in `native/grasql/benches/parser_benchmark.rs`. These benchmarks test performance with simple, medium, and complex GraphQL queries.

To run the benchmarks:

```shell
cd native/grasql
cargo bench
```

## Limitations

Current limitations include:

- **SQL Generation**: Still in early implementation stage with placeholder functionality
- **Schema Resolution**: Framework is defined but actual resolution logic is application-specific
- **GraphQL Features**: Currently does not support fragments, directives, or subscriptions
- **Query Complexity**: Complex filters and sorting are planned but not yet implemented

## Documentation

Further documentation can be found at <https://hexdocs.pm/grasql>.

## Development

```shell
mix deps.get          # Get dependencies
mix compile           # Compile the project
mix test              # Run the tests
mix docs              # Generate documentation
```

## License

GraSQL is licensed under the [Apache-2.0 License](LICENSE).
