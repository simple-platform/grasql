defmodule GraSQL.Application do
  @moduledoc """
  GraSQL Application module.

  Responsible for starting the GraSQL application and its supervision tree.
  Configuration is automatically loaded when the native implementation is
  initialized.

  ## Configuration

  GraSQL can be configured in your application's config.exs file:

  ```elixir
  config :grasql,
    query_cache_max_size: 2000,
    max_query_depth: 15,
    schema_resolver: MyApp.SchemaResolver
  ```

  See `GraSQL.Config` for all available configuration options.
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
