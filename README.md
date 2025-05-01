# GraSQL

[![Package Version](https://img.shields.io/hexpm/v/grasql)](https://hex.pm/packages/grasql)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/grasql/)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)

A high-performance GraphQL to SQL compiler optimized for PostgreSQL that generates efficient SQL directly from GraphQL queries.

## Overview

GraSQL transforms GraphQL queries into highly optimized PostgreSQL SQL statements. It eliminates the N+1 query problem and reduces application-layer processing by generating SQL that returns complete nested data structures as JSON directly from the database.

The library uses a resolver approach for schema mapping and permissions, making it highly adaptable to different database schemas and authorization requirements.

## Features

- **High Performance**:
  - Generate optimized SQL that returns fully structured JSON results directly from PostgreSQL
  - Intelligent query parsing cache eliminates redundant processing
  - Single-round-trip database communication
- **Complete Query Support**:
  - Simple and complex field selection
  - Nested queries with arbitrary depth
  - Filtering at root and nested levels
  - Sorting and pagination
  - Aggregation functions
- **Powerful Schema Resolution**:
  - Map GraphQL types to database tables/schemas
  - Define complex relationships (one-to-one, one-to-many, many-to-many)
  - Apply permission filtering
- **Security**:
  - Fully parameterized queries to prevent SQL injection
  - Context-aware resolvers for authentication/authorization
- **Developer Experience**:
  - Clean separation between schema definition and query execution
  - No need to write SQL or resolver functions for each field
  - Built with Rust for performance-critical components

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

### 1. Define a Schema Resolver

The Schema Resolver maps GraphQL types to your database tables and relationships:

```elixir
defmodule MyApp.GraphQLResolver do
  @behaviour GraSQL.SchemaResolver

  @impl true
  def resolve_table(table, ctx) do
    # Map GraphQL type to database table
    # Add tenant/user filtering if needed
    %{
      schema: "public",
      name: table.name,
      # Add other metadata as needed
    }
  end

  @impl true
  def resolve_relationship(relationship, ctx) do
    # Map GraphQL field to database relationship
    %{
      source_table: relationship.source_table,
      target_table: relationship.target_table,
      join_type: :inner,
      conditions: [
        %{
          source_column: "id",
          target_column: "#{relationship.source_table}_id"
        }
      ]
    }
  end
end
```

### 2. Execute Queries

Use the `GraSQL` module to parse GraphQL and generate SQL:

```elixir
query = """
{
  users(where: { status: { _eq: "active" } }) {
    id
    name
    posts(limit: 5, order_by: { created_at: desc }) {
      title
      body
    }
  }
}
"""

variables = %{}
context = %{user_id: current_user.id, tenant: "my_tenant"}

case GraSQL.generate_sql(query, variables, MyApp.GraphQLResolver, context) do
  {:ok, sql, params} ->
    # Execute the SQL with your database client
    Postgrex.query!(conn, sql, params)

  {:error, reason} ->
    # Handle error
end
```

Behind the scenes, GraSQL intelligently caches parsed queries to avoid redundant processing, ensuring optimal performance even for complex GraphQL operations.

## Limitations

GraSQL currently does not support:

- **GraphQL Fragments**: Custom fragments for reusable selection sets
- **GraphQL Directives**: Annotations like @include and @skip
- **GraphQL Subscriptions**: Real-time data subscriptions

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
