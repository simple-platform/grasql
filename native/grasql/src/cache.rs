use crate::types::ParsedQueryInfo;
use moka::sync::Cache;
use once_cell::sync::Lazy;
use std::sync::RwLock;
use std::time::Duration;
use xxhash_rust::xxh3::xxh3_64;

/// Global cache for parsed GraphQL queries with automatic LRU eviction and TTL
pub static QUERY_CACHE: Lazy<Cache<String, ParsedQueryInfo>> = Lazy::new(|| {
    Cache::builder()
        .max_capacity(100)
        .time_to_live(Duration::from_secs(60))
        .build()
});

/// Initialize the cache with the specified capacity and TTL
pub fn init_cache(max_size: usize, ttl_seconds: u64) {
    let new_cache = Cache::builder()
        .max_capacity(max_size as u64)
        .time_to_live(Duration::from_secs(ttl_seconds))
        .build();

    if let Ok(mut cache) = QUERY_CACHE.write() {
        *cache = new_cache;
    }
}

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
    if let Ok(cache) = QUERY_CACHE.read() {
        cache.insert(query_id.to_string(), parsed_query_info);
    }
}

/// Get a parsed query from the cache
pub fn get_from_cache(query_id: &str) -> Option<ParsedQueryInfo> {
    if let Ok(cache) = QUERY_CACHE.read() {
        return cache.get(query_id).map(|v| v.clone());
    }
    None
}
