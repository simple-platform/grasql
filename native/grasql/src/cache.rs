/// Cache management module for GraSQL
///
/// This module provides functionality for caching parsed GraphQL queries
/// to improve performance for repeated queries. It includes utilities for
/// generating query IDs, storing query information, and cleaning expired entries.
use crate::types::{CacheEntry, ParsedQueryInfo};
use dashmap::DashMap;
use once_cell::sync::Lazy;
use std::time::SystemTime;
use xxhash_rust::xxh3::xxh3_64;

/// Global cache for parsed GraphQL queries
pub static QUERY_CACHE: Lazy<DashMap<String, CacheEntry>> = Lazy::new(DashMap::new);

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
    QUERY_CACHE.insert(
        query_id.to_string(),
        CacheEntry {
            parsed_query_info,
            timestamp: SystemTime::now(),
        },
    );
}

/// Clean up expired cache entries
pub fn clean_cache(ttl: u64) {
    let now = SystemTime::now();
    QUERY_CACHE.retain(|_, entry| {
        if let Ok(elapsed) = now.duration_since(entry.timestamp) {
            elapsed.as_secs() < ttl
        } else {
            true
        }
    });
}

/// Evict the oldest entry from the cache
pub fn evict_oldest_entry() {
    let mut oldest_time = SystemTime::now();
    let mut oldest_key = None;

    for entry in QUERY_CACHE.iter() {
        if entry.timestamp < oldest_time {
            oldest_time = entry.timestamp;
            oldest_key = Some(entry.key().clone());
        }
    }

    if let Some(key) = oldest_key {
        QUERY_CACHE.remove(&key);
    }
}
