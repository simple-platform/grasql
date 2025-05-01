use crate::config::CONFIG;
use crate::types::ParsedQueryInfo;
use moka::sync::Cache;
use once_cell::sync::Lazy;
use std::time::Duration;
use xxhash_rust::xxh3::xxh3_64;

/// Create a cache based on the current configuration
fn create_cache_from_config() -> Cache<String, ParsedQueryInfo> {
    // Get current configuration or use defaults if not initialized
    let config_guard = CONFIG
        .lock()
        .unwrap_or_else(|_| panic!("CONFIG lock poisoned"));

    let (max_size, ttl) = match &*config_guard {
        Some(cfg) => (cfg.query_cache_max_size as u64, cfg.query_cache_ttl_seconds),
        None => (1000, 3600), // Default values if CONFIG not initialized yet
    };

    Cache::builder()
        .max_capacity(max_size)
        .time_to_live(Duration::from_secs(ttl))
        .build()
}

/// Global cache for parsed GraphQL queries with automatic LRU eviction and TTL
/// Initialized with user configuration values when first accessed
pub static QUERY_CACHE: Lazy<Cache<String, ParsedQueryInfo>> =
    Lazy::new(|| create_cache_from_config());

/// Converts query string to a unique query ID using xxHash algorithm
///
/// This function generates a consistent hash for a given GraphQL query string,
/// which is used as the cache key. The xxHash algorithm is used for its
/// speed and quality.
#[inline]
pub fn generate_query_id(query: &str) -> String {
    let hash = xxh3_64(query.as_bytes());
    format!("{:x}", hash)
}

/// Add a parsed query to the cache
pub fn add_to_cache(query_id: &str, parsed_query_info: ParsedQueryInfo) {
    QUERY_CACHE.insert(query_id.to_string(), parsed_query_info);
}

/// Get a parsed query from the cache
pub fn get_from_cache(query_id: &str) -> Option<ParsedQueryInfo> {
    QUERY_CACHE.get(query_id).map(|v| v.clone())
}
