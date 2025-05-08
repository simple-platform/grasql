use crate::config::CONFIG;
use crate::types::{CachedQueryInfo, ParsedQueryInfo, ResolutionRequest};
use moka::sync::Cache;
use once_cell::sync::Lazy;
use std::time::Duration;
use xxhash_rust::xxh3::xxh3_64;

/// Create a cache based on the current configuration
#[inline(always)]
fn create_cache_from_config() -> Cache<String, CachedQueryInfo> {
    // Get current configuration or use defaults if not initialized
    let config_guard = match CONFIG.lock() {
        Ok(guard) => guard,
        Err(poisoned) => {
            // Log the error
            eprintln!("WARNING: CONFIG lock poisoned, using recovered lock");
            poisoned.into_inner()
        }
    };

    let (max_size, ttl) = match &*config_guard {
        Some(cfg) => (cfg.query_cache_max_size as u64, cfg.query_cache_ttl_seconds),
        None => (1000, 600), // Default values if CONFIG not initialized yet
    };

    Cache::builder()
        .max_capacity(max_size)
        .time_to_live(Duration::from_secs(ttl))
        .build()
}

/// Global cache for parsed GraphQL queries with automatic LRU eviction and TTL
/// Initialized with user configuration values when first accessed
///
/// # Thread Safety
///
/// This cache is thread-safe and can be accessed concurrently from multiple threads
/// without any additional synchronization. The underlying implementation uses sharded
/// locks to minimize contention.
///
/// # Cache Behavior
///
/// The cache implements both:
/// - LRU (Least Recently Used) eviction when cache size exceeds max_capacity
/// - TTL (Time-To-Live) expiration based on configuration
///
/// # Performance Considerations
///
/// This cache is optimized for high-throughput environments and is a critical
/// component for achieving 100K+ QPS performance targets.
pub static QUERY_CACHE: Lazy<Cache<String, CachedQueryInfo>> =
    Lazy::new(|| create_cache_from_config());

/// Converts query string to a unique query ID using xxHash algorithm
///
/// This function generates a consistent hash for a given GraphQL query string,
/// which is used as the cache key. The xxHash algorithm is used for its
/// speed and quality.
///
/// # Performance Considerations
///
/// The xxHash3 algorithm is chosen for its exceptional performance characteristics:
/// - Much faster than cryptographic hashes (SHA, MD5)
/// - Better distribution than simple hashing algorithms
/// - Very low collision rate for GraphQL queries
#[inline(always)]
pub fn generate_query_id(query: &str) -> String {
    let hash = xxh3_64(query.as_bytes());
    format!("{:x}", hash)
}

/// Add a parsed query to the cache
///
/// This function converts the ParsedQueryInfo to a thread-safe CachedQueryInfo
/// and stores it in the global query cache using the query ID as the key.
///
/// # Memory Safety
///
/// The conversion to CachedQueryInfo properly preserves all necessary references
/// to ensure memory safety and thread safety. The Document pointer is only valid
/// while the AST context exists, which is guaranteed by the Arc wrapping the context.
#[inline(always)]
pub fn add_to_cache(query_id: &str, parsed_query_info: ParsedQueryInfo) {
    // Convert ParsedQueryInfo to CachedQueryInfo (thread-safe) version
    let cached_info: CachedQueryInfo = parsed_query_info.into();
    QUERY_CACHE.insert(query_id.to_string(), cached_info);
}

/// Get a parsed query from the cache
///
/// This function retrieves a cached query by its ID and returns a clone
/// of the CachedQueryInfo. The clone is lightweight as it only involves
/// incrementing reference counts for the Arc-wrapped AST context.
///
/// # Returns
///
/// - Some(CachedQueryInfo) if the query is in the cache
/// - None if the query is not in the cache or has expired
#[inline(always)]
pub fn get_from_cache(query_id: &str) -> Option<CachedQueryInfo> {
    QUERY_CACHE.get(query_id).map(|val| val.clone())
}

/// Insert a CachedQueryInfo directly into the cache - for testing only
///
/// This function allows tests to manipulate the cache directly, bypassing
/// the normal flow of parsing and converting a query. It's useful for testing
/// edge cases and cache behavior in controlled environments.
///
/// # Note
///
/// This function is only available in test builds and should not be used
/// in production code.
#[cfg(any(test, feature = "test-utils"))]
pub fn insert_raw_for_test(query_id: &str, cached_info: CachedQueryInfo) {
    QUERY_CACHE.insert(query_id.to_string(), cached_info);
}

/// Add a parsed query to the cache with its resolution request
///
/// This function converts the ParsedQueryInfo to a thread-safe CachedQueryInfo,
/// includes the ResolutionRequest, and stores it in the global query cache
/// using the query ID as the key.
///
/// # Memory Safety
///
/// The conversion to CachedQueryInfo properly preserves all necessary references
/// to ensure memory safety and thread safety. The Document pointer is only valid
/// while the AST context exists, which is guaranteed by the Arc wrapping the context.
#[inline(always)]
pub fn add_to_cache_with_request(
    query_id: &str,
    parsed_query_info: ParsedQueryInfo,
    resolution_request: ResolutionRequest,
) {
    // Convert ParsedQueryInfo to CachedQueryInfo (thread-safe) version
    let mut cached_info: CachedQueryInfo = parsed_query_info.into();

    // Store the ResolutionRequest in the cached info
    cached_info.resolution_request = Some(resolution_request);

    QUERY_CACHE.insert(query_id.to_string(), cached_info);
}
