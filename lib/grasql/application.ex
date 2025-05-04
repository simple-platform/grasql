defmodule GraSQL.Application do
  @moduledoc """
  GraSQL Application module.

  Starts the GraSQL application and its supervision tree. Configuration is
  automatically loaded during initialization.

  ## Configuration

  Configure GraSQL in your application's config.exs file:

  ```elixir
  config :grasql,
    # Caching settings
    query_cache_max_size: 2000,
    query_cache_ttl_seconds: 600,

    # Performance limits
    max_query_depth: 15,
    string_interner_capacity: 10_000,

    # Schema resolution
    schema_resolver: MyApp.SchemaResolver
  ```

  See `GraSQL.Config` for details on all configuration options.
  """
  use Application
  require Logger

  @doc false
  def start(_type, _args) do
    # Load and validate configuration
    {:ok, _config} = GraSQL.Config.load_and_validate()

    # Start a supervision tree if needed in the future
    children = []
    opts = [strategy: :one_for_one, name: GraSQL.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
