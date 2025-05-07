import Config

# Common configuration for all environments
config :grasql,
  # Default schema resolver (should be overridden in specific environments)
  schema_resolver: nil,
  # Query depth limits
  max_query_depth: 15,
  # Cache settings
  query_cache_max_size: 1000,
  query_cache_ttl_seconds: 600

# Import environment specific config
import_config "#{config_env()}.exs"
