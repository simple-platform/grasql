defmodule GraSQL.Application do
  @moduledoc """
  OTP Application module for GraSQL.

  Responsible for starting and managing the GraSQL application, including:
  - Loading and validating global configuration
  - Starting the schema resolver cache
  - Managing the supervision tree

  This module is automatically started when the GraSQL application starts.
  """

  use Application
  require Logger

  @doc false
  def start(_type, _args) do
    # Load and validate global configuration
    case GraSQL.Config.load_and_validate() do
      {:ok, config} ->
        # Store the validated config in application env
        Application.put_env(:grasql, :__config__, config)
        Logger.debug("GraSQL initialized with global configuration")

      {:error, reason} ->
        if Mix.env() != :test do
          Logger.error("GraSQL configuration validation failed: #{reason}")
          raise "GraSQL configuration validation failed: #{reason}"
        end
    end

    # Start a supervision tree with resolver cache
    children = [
      GraSQL.SchemaResolverCache
    ]

    opts = [strategy: :one_for_one, name: GraSQL.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
