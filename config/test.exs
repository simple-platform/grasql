import Config

# Test-specific configuration
config :grasql,
  # Use TestResolver for tests
  schema_resolver: GraSQL.TestResolver
