/// NIF interface module for GraSQL
///
/// This module provides the NIFs (Native Implemented Functions) that are exposed to Elixir.
/// These functions are the bridge between Elixir and the Rust implementation of GraSQL.
use crate::atoms;
use crate::cache::{add_to_cache, generate_query_id, get_from_cache};
use crate::config::{Config, CONFIG};
use crate::parser::parse_graphql;
use crate::sql::generate_sql;
use crate::types::GraphQLOperationKind;

use rustler::{Encoder, Env, Error, Term};

/// Initialize the GraSQL engine with the provided configuration
///
/// This function is called from Elixir to initialize GraSQL with a configuration struct.
/// It stores the configuration in a global state for use by other functions.
#[rustler::nif(name = "do_init")]
pub fn do_init(env: Env<'_>, config: Config) -> rustler::NifResult<Term<'_>> {
    // Store the configuration in the global state
    match CONFIG.lock() {
        Ok(mut cfg) => {
            *cfg = Some(config.clone());

            // The cache will use this config when it's first accessed
            Ok((atoms::ok()).encode(env))
        }
        Err(_) => Err(Error::Term(Box::new("Failed to acquire config lock"))),
    }
}

/// Parse a GraphQL query string
///
/// This function parses a GraphQL query string and returns information about the
/// operation kind, name, and a unique query ID that can be used for SQL generation.
#[rustler::nif(name = "do_parse_query")]
pub fn do_parse_query(env: Env<'_>, query: String) -> rustler::NifResult<Term<'_>> {
    // Get the current configuration
    let _config = match CONFIG.lock() {
        Ok(cfg) => match &*cfg {
            Some(c) => c.clone(),
            None => return Err(Error::Term(Box::new("GraSQL not initialized"))),
        },
        Err(_) => return Err(Error::Term(Box::new("Failed to acquire config lock"))),
    };

    // Generate a unique ID for this query
    let query_id = generate_query_id(&query);

    // Check if we have this query in cache
    if let Some(parsed_query_info) = get_from_cache(&query_id) {
        // Cache hit - return the cached parsed query info
        let operation_kind = match parsed_query_info.operation_kind {
            GraphQLOperationKind::Query => atoms::query(),
            GraphQLOperationKind::Mutation => atoms::mutation(),
            GraphQLOperationKind::Subscription => atoms::subscription(),
        };

        let result = (
            atoms::ok(),
            query_id.clone(),
            operation_kind,
            parsed_query_info.operation_name.clone().unwrap_or_default(),
        );

        return Ok(result.encode(env));
    }

    // Parse the query
    let parsed_query_info = match parse_graphql(&query) {
        Ok(info) => info,
        Err(e) => return Err(Error::Term(Box::new(e))),
    };

    // Add to cache
    add_to_cache(&query_id, parsed_query_info.clone());

    // Return the operation info
    let operation_kind = match parsed_query_info.operation_kind {
        GraphQLOperationKind::Query => atoms::query(),
        GraphQLOperationKind::Mutation => atoms::mutation(),
        GraphQLOperationKind::Subscription => atoms::subscription(),
    };

    let result = (
        atoms::ok(),
        query_id,
        operation_kind,
        parsed_query_info.operation_name.unwrap_or_default(),
    );

    Ok(result.encode(env))
}

/// Generate SQL from a parsed GraphQL query
///
/// This function generates SQL from a previously parsed GraphQL query,
/// identified by its query ID. It also takes variables that can be used
/// in the query.
#[rustler::nif(name = "do_generate_sql")]
pub fn do_generate_sql<'a>(
    env: Env<'a>,
    query_id: String,
    _variables: Term<'a>,
) -> rustler::NifResult<Term<'a>> {
    // Get the current configuration
    let _config = match CONFIG.lock() {
        Ok(cfg) => match &*cfg {
            Some(c) => c.clone(),
            None => return Err(Error::Term(Box::new("GraSQL not initialized"))),
        },
        Err(_) => return Err(Error::Term(Box::new("Failed to acquire config lock"))),
    };

    // Try to get from cache
    let parsed_query_info = match get_from_cache(&query_id) {
        Some(info) => info,
        None => return Err(Error::Term(Box::new("Query not found in cache"))),
    };

    // Generate SQL
    let sql = generate_sql(&parsed_query_info);

    // Create an empty list for parameters
    let params: Vec<Term<'a>> = Vec::new();

    Ok((atoms::ok(), sql, params).encode(env))
}
