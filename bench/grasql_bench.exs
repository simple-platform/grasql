# GraSQL Performance Benchmarks
#
# Run with:
#   mix run bench/grasql_bench.exs
#
# Or with HTML output:
#   mix run bench/grasql_bench.exs --output html

# Sample benchmark queries
queries = %{
  "simple_query" => "{ users { id name } }",

  "medium_query" => """
  query GetUser($id: ID!) {
    user(id: $id) {
      id
      name
      email
      posts(first: 5, orderBy: { createdAt: DESC }) {
        id
        title
        body
        tags { id name }
      }
    }
  }
  """,

  "complex_query" => """
  query GetUserWithData($userId: ID!) {
    user(id: $userId) {
      id
      name
      email
      profile {
        avatar
        bio
        location
        website
      }
      posts(
        first: 10
        orderBy: { createdAt: DESC }
        where: { published: { _eq: true } }
      ) {
        id
        title
        body
        createdAt
        updatedAt
        tags {
          id
          name
        }
        comments(first: 5) {
          id
          body
          author {
            id
            name
          }
        }
      }
      followers(first: 10) {
        id
        name
      }
      following(first: 10) {
        id
        name
      }
    }
  }
  """,

  "deeply_nested_query" => """
  {
    organizations {
      id
      name
      departments {
        id
        name
        teams {
          id
          name
          projects {
            id
            name
            tasks {
              id
              name
              subtasks {
                id
                name
                assignee {
                  id
                  name
                  skills {
                    id
                    name
                    level
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  """,

  "complex_filters_query" => """
  {
    users(where: {
      _and: [
        { name: { _like: "%John%" } },
        { email: { _ilike: "%example.com" } },
        {
          _or: [
            { age: { _gt: 18 } },
            { status: { _eq: "ACTIVE" } }
          ]
        },
        {
          profile: {
            _and: [
              { verified: { _eq: true } },
              {
                location: {
                  city: { _eq: "New York" }
                }
              }
            ]
          }
        }
      ]
    }) {
      id
      name
      email
    }
  }
  """,

  "aggregation_query" => """
  {
    users_aggregate {
      aggregate {
        count
        sum {
          age
          score
        }
        avg {
          age
        }
        max {
          age
        }
        min {
          age
        }
      }
      nodes {
        id
        name
      }
    }
  }
  """,

  "pagination_sorting_query" => """
  {
    users(
      limit: 10,
      offset: 20,
      order_by: { name: asc, created_at: desc }
    ) {
      id
      name
      email
    }
  }
  """,

  "mutation_query" => """
  mutation {
    insert_users(
      objects: [
        { name: "John", email: "john@example.com" },
        { name: "Jane", email: "jane@example.com" }
      ]
    ) {
      returning {
        id
        name
        profile {
          avatar
        }
      }
      affected_rows
    }
  }
  """
}

variables = %{
  "id" => "123",
  "userId" => "456"
}

# Configure the benchmark
Benchee.run(
  %{
    "parse_query" => fn {_name, query} ->
      GraSQL.parse_query(query)
    end,

    "generate_sql" => fn {_name, query} ->
      # Only measure SQL generation (not parsing)
      {:ok, query_id, _, _, _} = GraSQL.parse_query(query)
      GraSQL.Native.generate_sql(query_id, variables)
    end,

    "full_pipeline" => fn {_name, query} ->
      # Measure the full pipeline (parse + generate SQL)
      GraSQL.generate_sql(query, variables)
    end
  },
  inputs: queries |> Enum.map(fn {name, query} -> {name, {name, query}} end) |> Enum.into(%{}),
  warmup: 2,
  time: 5,
  memory_time: 3,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.HTML, file: "bench/output/benchmarks.html", auto_open: false}
  ],
  print: [
    benchmarking: true,
    configuration: true,
    fast_warning: true
  ]
)

# Test concurrent performance
IO.puts("\n\nTesting concurrent performance...\n")

# This benchmark measures how the system performs under concurrent load
# simulating multiple simultaneous requests
concurrent_inputs = Map.take(queries, ["simple_query", "medium_query", "complex_query"])

# Define a function that will be called concurrently multiple times
concurrent_fn = fn {_, query} ->
  GraSQL.generate_sql(query, variables)
end

# Define concurrency levels to test
concurrency_levels = [1, 2, 4, 8, 16, 32]

# Run benchmarks for each concurrency level
for level <- concurrency_levels do
  IO.puts("\nConcurrency level: #{level}")

  # Create the tasks
  tasks = for _ <- 1..level do
    # Randomly select one of the queries for each task
    query = Enum.random(concurrent_inputs)
    Task.async(fn -> concurrent_fn.(query) end)
  end

  # Time how long it takes to complete all tasks
  {time, results} = :timer.tc(fn -> Task.yield_many(tasks, 5000) end)

  # Check if all tasks completed successfully
  completed = results |> Enum.count(fn {_, result} -> result != nil end)

  if completed > 0 do
    IO.puts("Completed: #{completed}/#{level} tasks")
    IO.puts("Total time: #{time / 1_000_000} seconds")
    IO.puts("Average time per task: #{time / (1_000_000 * completed)} seconds")

    # Calculate approximate throughput (queries per second)
    throughput = completed / (time / 1_000_000)
    IO.puts("Approximate throughput: #{Float.round(throughput, 2)} queries/second")
  else
    IO.puts("No tasks completed within timeout")
  end
end
