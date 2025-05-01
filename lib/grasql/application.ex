defmodule GraSQL.Application do
  @moduledoc """
  GraSQL Application module.

  Responsible for automatic initialization of the GraSQL engine at application startup.

  ## Configuration

  GraSQL can be configured in your application's config.exs file:

  ```elixir
  config :grasql,
    max_cache_size: 2000,
    max_query_depth: 15
  ```

  See `GraSQL.Config` for all available configuration options.
  """
  use Application
  alias GraSQL.Config
  alias GraSQL.Native

  @doc false
  def start(_type, _args) do
    # Initialize GraSQL with configuration from application env
    config = load_config()
    :ok = init_engine(config)

    # Start a supervision tree if needed in the future
    children = []
    opts = [strategy: :one_for_one, name: GraSQL.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Initialize the GraSQL engine
  @doc false
  defp init_engine(config) do
    case Config.validate(config) do
      {:ok, valid_config} ->
        # Convert config for Rust NIF
        native_config = Config.to_native_config(valid_config)
        Native.init(native_config)

      {:error, _} = error ->
        error
    end
  end

  # Load configuration from application environment
  defp load_config do
    app_config = Application.get_all_env(:grasql)

    # Only include fields that exist in Config struct to avoid errors
    config_fields = Config.__struct__() |> Map.keys() |> Enum.filter(&(&1 != :__struct__))

    # Filter app_config to only include valid config fields
    valid_config =
      app_config
      |> Enum.filter(fn {key, _} -> key in config_fields end)
      |> Enum.into(%{})

    # Create config struct with application settings
    struct(Config, valid_config)
  end
end
