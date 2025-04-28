defmodule GraSQL do
  @moduledoc """
  GraSQL provides a bridge between GraphQL and SQL databases.

  This library allows for efficient translation of GraphQL queries into optimized SQL,
  with a focus on performance, memory efficiency, and developer-friendly interfaces.

  The core functionality includes:
  - GraphQL query parsing and analysis
  - Schema needs determination
  - SQL generation with parameter handling
  - Result mapping from SQL to GraphQL responses
  """

  alias GraSQL.Native

  @doc """
  Generates SQL from a GraphQL query.

  This function provides a simplified API by combining both phases of the
  SQL generation process into a single call:
  1. Parse and analyze the GraphQL query (Phase 1)
  2. Apply the resolver methods to enrich the analysis
  3. Generate SQL from the enriched analysis (Phase 2)

  The resolver must implement these methods:
  - `resolve_tables/2`: Maps GraphQL types to database tables
  - `resolve_relationships/2`: Defines relationships between tables
  - `set_permissions/2`: Applies access control rules
  - `set_overrides/2`: Provides custom overrides (only used for mutations)

  ## Parameters

  - `query`: The GraphQL query string
  - `variables`: Variables for the GraphQL query (JSON string or map)
  - `resolver`: Module implementing the required resolver methods
  - `ctx`: Context map passed to all resolver functions (default: %{})

  ## Returns

  - `{:ok, sql_result}`: Successfully generated SQL
  - `{:error, reason}`: Error encountered during parsing, analysis, or SQL generation

  ## Example

  ```elixir
  query = "query GetUserPosts($userId: ID!) { user(id: $userId) { posts { id title } } }"
  variables = %{"userId" => "123"}
  ctx = %{current_user_id: "456"}

  {:ok, sql_result} = GraSQL.generate_sql(query, variables, MyApp.Resolver, ctx)
  ```
  """
  def generate_sql(query, variables, resolver, ctx \\ %{}) do
    variables_json = prepare_variables(variables)
    validate_resolver(resolver)

    # Phase 1: Parse and analyze the GraphQL query
    with {:ok, initial_qst} <- Native.parse_and_analyze_query(query, variables_json) do
      is_mutation = mutation?(initial_qst)
      validate_mutation_resolver(resolver, is_mutation)

      # Apply resolver methods and generate SQL
      enriched_qst = enrich_query(initial_qst, resolver, ctx, is_mutation)
      Native.generate_sql(enriched_qst, %{}, %{})
    end
  end

  # Convert variables to JSON string
  defp prepare_variables(variables) do
    case variables do
      %{} = map ->
        Jason.encode!(map)

      binary when is_binary(binary) ->
        binary

      nil ->
        "{}"

      other ->
        raise ArgumentError,
              "variables must be a map, JSON string, or nil, got: #{inspect(other)}"
    end
  end

  # Validate that resolver implements required methods
  defp validate_resolver(resolver) do
    required_methods = [:resolve_tables, :resolve_relationships, :set_permissions]

    for method <- required_methods do
      unless Code.ensure_loaded?(resolver) and function_exported?(resolver, method, 2) do
        raise ArgumentError, "resolver must implement #{method}/2"
      end
    end
  end

  # Validate that resolver implements set_overrides/2 for mutations
  defp validate_mutation_resolver(resolver, true) do
    unless Code.ensure_loaded?(resolver) and function_exported?(resolver, :set_overrides, 2) do
      raise ArgumentError, "resolver must implement set_overrides/2 for mutations"
    end
  end

  defp validate_mutation_resolver(_resolver, false), do: :ok

  # Apply resolver methods to enrich the query
  defp enrich_query(qst, resolver, ctx, is_mutation) do
    qst
    |> resolver.resolve_tables(ctx)
    |> resolver.resolve_relationships(ctx)
    |> resolver.set_permissions(ctx)
    |> then(fn enriched_qst ->
      if is_mutation do
        resolver.set_overrides(enriched_qst, ctx)
      else
        enriched_qst
      end
    end)
  end

  # Helper function to determine if the analysis represents a mutation
  defp mutation?(qst) do
    # Implementation depends on the structure of QST from the Rust NIF
    Map.get(qst, :operation_type) == "mutation"
  end
end
