# GraSQL

[![Package Version](https://img.shields.io/hexpm/v/grasql)](https://hex.pm/packages/grasql)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/grasql/)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)

A high-performance GraphQL to SQL compiler optimized for PostgreSQL, used by the Simple Platform.

## Overview

GraSQL is designed to transform GraphQL queries into highly optimized SQL with extreme performance (100K+ queries/second). The library uses a two-phase compilation approach that efficiently handles schema resolution, permissions, and query optimization.

## Architecture

For detailed architecture information, see the [Architecture Document](docs/architecture.md).

## Features

- Ultra-fast GraphQL to SQL compilation using Rust (via Rustler)
- Two-phase compilation for optimal performance and flexibility
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

GraSQL uses a two-phase approach for maximum efficiency:

```elixir
defmodule MyApp.GraphQL do
  alias GraSQL

  def execute_query(query, variables, user_id) do
    # Phase 1: Analyze query to determine schema needs
    case GraSQL.analyze_query(query, variables) do
      {:ok, analysis} ->
        # Resolve schema based on query needs
        schema_info = MyApp.Database.get_schema_info(analysis.schema_needs)

        # Set up options with permissions
        options = %GraSQL.SqlGenOptions{
          permissions: [
            GraSQL.Filter.equal(GraSQL.ColumnRef.new("users.id"), user_id)
          ],
          overrides: [],
          include_metadata: false
        }

        # Phase 2: Generate SQL with schema info and permissions
        case GraSQL.generate_sql(analysis, schema_info, options) do
          {:ok, sql_result} ->
            # Execute the SQL with your database client
            MyApp.Database.execute(sql_result.sql, sql_result.parameters)

          {:error, error} ->
            {:error, handle_error(error)}
        end

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
