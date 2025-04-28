defmodule GraSQL.SchemaResolverBehavior do
  @moduledoc """
  Behavior for schema resolution in GraSQL.

  This behavior defines the interface for modules that want to provide
  custom schema resolution logic. Applications using GraSQL MUST implement
  this behavior in a module and provide it when calling `GraSQL.generate_sql/4`.

  Implementers must provide functions to:

  1. Resolve tables: Maps GraphQL types to database tables
  2. Resolve relationships: Defines relationships between tables
  3. Set permissions: Applies access control rules
  4. Set overrides: Provides custom overrides (only used for mutations)

  This allows consumers of the GraSQL library to customize how GraphQL entities and
  relationships map to database tables, and to apply permissions and overrides.

  Each callback function receives:
  - A Query Structure Tree (QST) representing the GraphQL query structure
  - A context parameter passed through from the original `generate_sql/4` call

  ## Example Implementation

  ```elixir
  defmodule MyApp.Resolver do
    @behaviour GraSQL.SchemaResolverBehavior

    def resolve_tables(qst, ctx) do
      # Map GraphQL types to database tables
      Map.update(qst, :tables, %{}, fn tables ->
        Map.merge(tables, %{
          "User" => %{schema: "public", table: "users", columns: ["id", "name", "email"]},
          "Post" => %{schema: "public", table: "posts", columns: ["id", "title", "content", "user_id"]}
        })
      end)
    end

    def resolve_relationships(qst, ctx) do
      # Define relationships between tables
      Map.update(qst, :relationships, %{}, fn relationships ->
        Map.merge(relationships, %{
          "User.posts" => %{
            parent_table: "users",
            child_table: "posts",
            parent_key: "id",
            child_key: "user_id"
          }
        })
      end)
    end

    def set_permissions(qst, ctx) do
      # Apply permission filters
      user_id = Map.get(ctx, :current_user_id)

      Map.update(qst, :permissions, [], fn permissions ->
        [
          %{field: "users.id", operation: "equals", value: user_id},
          %{
            operation: "or",
            conditions: [
              %{field: "posts.user_id", operation: "equals", value: user_id},
              %{field: "posts.is_public", operation: "equals", value: true}
            ]
          }
          | permissions
        ]
      end)
    end

    def set_overrides(qst, ctx) do
      # Set overrides for mutations
      user_id = Map.get(ctx, :current_user_id)

      Map.update(qst, :overrides, [], fn overrides ->
        [
          %{field: "posts.updated_at", value: :current_timestamp},
          %{field: "posts.updated_by", value: user_id}
          | overrides
        ]
      end)
    end
  end
  ```

  And then use it like:

  ```elixir
  query = "query GetUserPosts($userId: ID!) { user(id: $userId) { posts { id title } } }"
  variables = %{"userId" => "123"}
  ctx = %{current_user_id: "user-456"}

  {:ok, sql_result} = GraSQL.generate_sql(query, variables, MyApp.Resolver, ctx)
  ```
  """

  @doc """
  Maps GraphQL types to database tables.

  This function takes the initial QST and adds table mapping information,
  specifying which database tables and columns correspond to GraphQL types.

  The ctx parameter contains any contextual information needed for resolution.
  """
  @callback resolve_tables(qst :: map(), ctx :: map()) :: map()

  @doc """
  Defines relationships between tables.

  This function takes the QST (after table resolution) and adds relationship
  information, specifying how tables are related to each other.

  The ctx parameter contains any contextual information needed for resolution.
  """
  @callback resolve_relationships(qst :: map(), ctx :: map()) :: map()

  @doc """
  Applies access control rules through filters.

  This function takes the QST (after relationship resolution) and adds
  permission filters to restrict data access based on user context or other rules.

  The ctx parameter contains any contextual information needed for filtering.
  """
  @callback set_permissions(qst :: map(), ctx :: map()) :: map()

  @doc """
  Provides custom overrides for mutations.

  This function is only called for mutation operations. It takes the QST
  (after permission setting) and adds value overrides for specific fields.

  The ctx parameter contains any contextual information needed for overrides.
  """
  @callback set_overrides(qst :: map(), ctx :: map()) :: map()
end
