# Make sure support files are loaded first
Code.require_file("support/test_resolver.ex", __DIR__)

# Start ExUnit
ExUnit.start()

# Configure tests to use the TestResolver - this should happen *after* support files are loaded
Application.put_env(:grasql, :schema_resolver, GraSQL.TestResolver)

# Initialize the configuration
try do
  case GraSQL.Config.load_and_validate() do
    {:ok, config} ->
      Application.put_env(:grasql, :__config__, config)

    {:error, _} ->
      # Don't fail in test context
      :ok
  end
rescue
  _ -> :ok
end

# Initialize the ETS table manually for tests
try do
  :ets.new(:grasql_resolver_cache, [:named_table, :set, :public, read_concurrency: true])
rescue
  _ -> :ok
end

# Insert test resolver into ETS
:ets.insert(:grasql_resolver_cache, {:schema_resolver, GraSQL.TestResolver})
