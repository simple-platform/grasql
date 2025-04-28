# GraSQL

[![Package Version](https://img.shields.io/hexpm/v/grasql)](https://hex.pm/packages/grasql)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/grasql/)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)

A high-performance GraphQL to SQL compiler optimized for PostgreSQL, used by the Simple Platform.

## Overview

GraSQL is designed to transform GraphQL queries into highly optimized SQL with extreme performance (100K+ queries/second). The library uses a resolver approach that efficiently handles schema resolution, permissions, and query optimization.

## Architecture

For detailed architecture information, see the [Architecture Document](docs/architecture.md).

## Features

- Ultra-fast GraphQL to SQL compilation using Rust (via Rustler)
- Structured resolver approach for schema mapping and permissions
- Efficient schema resolution that minimizes memory usage
- Cross-schema query support for complex database structures
- Permission filtering and mutation value overrides
- Transaction-safe SQL generation
- Parameterized queries for security and performance
- Used and maintained by the Simple Platform

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

## Usage

GraSQL uses a resolver-based approach for maximum efficiency and clarity:

```elixir
defmodule MyApp.GraphQL do
  alias GraSQL

  # First, implement a resolver that maps GraphQL types to your database
  defmodule Resolver do
    # Map GraphQL types to database tables
    def resolve_tables(qst) do
      # Implementation that adds table information to the QST
      # ...
    end

    # Define relationships between tables
    def resolve_relationships(qst) do
      # Implementation that adds relationship information to the QST
      # ...
    end

    # Apply permission filters
    def set_permissions(qst) do
      # Implementation that adds permission filters to the QST
      # ...
    end

    # Set overrides for mutations (only called for mutation operations)
    def set_overrides(qst) do
      # Implementation that adds value overrides to the QST
      # ...
    end
  end

  def execute_query(query, variables, _user_id) do
    # Generate SQL using the resolver
    case GraSQL.generate_sql(query, variables, Resolver) do
      {:ok, sql_result} ->
        # Execute the SQL with your database client
        MyApp.Database.execute(sql_result.sql, sql_result.parameters)

      {:error, error} ->
        {:error, handle_error(error)}
    end
  end
end
```

## Performance

GraSQL achieves exceptional performance through:

- Rust-powered parsing and SQL generation
- Minimal memory usage with focused schema resolution
- Efficient binary encoding for cross-language operations
- Query optimization techniques
- Fast parameterization

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
