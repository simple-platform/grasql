/// Configuration module for GraSQL
///
/// This module defines the configuration structure and globals needed for the
/// GraSQL engine, handling settings related to naming conventions, operators,
/// caching, joins, and performance parameters.
use once_cell::sync::Lazy;
use rustler::{Atom, NifMap};
use std::collections::HashMap;
use std::sync::Mutex;

/// Configuration structure that mirrors the Elixir GraSQL.Config struct
#[derive(NifMap, Clone, Debug)]
pub struct Config {
    /// Field name suffix for aggregate operations
    pub aggregate_field_suffix: String,

    /// Parameter name used for single record queries
    pub single_query_param_name: String,

    /// Operator mappings from GraphQL to SQL
    pub operators: HashMap<String, String>,

    /// Maximum number of parsed queries to store in cache
    pub max_cache_size: usize,

    /// Time-to-live for cached queries in seconds
    pub cache_ttl: u64,

    /// Default join type for relationships
    pub default_join_type: Atom,

    /// Whether to skip join tables in many-to-many relationships
    pub skip_join_table: bool,

    /// Maximum allowed depth for nested GraphQL queries
    pub max_query_depth: usize,
}

/// Global configuration initialized during GraSQL.init
pub static CONFIG: Lazy<Mutex<Option<Config>>> = Lazy::new(|| Mutex::new(None));

/// Translates a GraphQL operator to SQL operator
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
