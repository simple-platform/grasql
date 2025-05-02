/// Configuration module for GraSQL
///
/// This module defines the configuration structure and globals needed for the
/// GraSQL engine, handling settings related to naming conventions, operators,
/// caching, and performance parameters.
use once_cell::sync::Lazy;
use rustler::NifMap;
use std::collections::HashMap;
use std::sync::Mutex;

/// Configuration structure that mirrors the Elixir GraSQL.Config struct
#[derive(NifMap, Clone, Debug)]
pub struct Config {
    /// Field name suffix for aggregate operations
    pub aggregate_field_suffix: String,

    /// Argument name used for primary key in single record queries
    pub primary_key_argument_name: String,

    /// Operator mappings from GraphQL to SQL
    pub operators: HashMap<String, String>,

    /// Maximum number of parsed queries to store in cache
    pub query_cache_max_size: usize,

    /// Time-to-live for cached queries in seconds
    pub query_cache_ttl_seconds: u64,

    /// Maximum allowed depth for nested GraphQL queries
    pub max_query_depth: usize,
}

/// Global configuration initialized during GraSQL.init
pub static CONFIG: Lazy<Mutex<Option<Config>>> = Lazy::new(|| Mutex::new(None));

/// Translates a GraphQL operator to SQL operator
#[inline(always)]
pub fn translate_operator(graphql_op: &str) -> &'static str {
    match graphql_op {
        "_eq" => "=",
        "_neq" => "<>",
        "_gt" => ">",
        "_lt" => "<",
        "_gte" => ">=",
        "_lte" => "<=",
        "_like" => "LIKE",
        "_ilike" => "ILIKE",
        "_in" => "IN",
        "_nin" => "NOT IN",
        "_is_null" => "IS NULL",
        _ => "=", // Default to equals if unknown
    }
}
