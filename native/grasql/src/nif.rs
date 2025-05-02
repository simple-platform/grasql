/// NIF interface module for GraSQL
///
/// This module provides the NIFs (Native Implemented Functions) that are exposed to Elixir.
/// These functions are the bridge between Elixir and the Rust implementation of GraSQL.
use crate::atoms;
use crate::cache::{add_to_cache, generate_query_id, get_from_cache};
use crate::config::CONFIG;
use crate::extraction::convert_paths_to_indices;
use crate::interning::{get_all_strings, intern_str};
use crate::parser::parse_graphql;
use crate::sql::generate_sql;
use crate::types::{CachedQueryInfo, ResolutionRequest};

use rustler::{Encoder, Env, Error, NifResult, Term};
use std::collections::HashMap;

/// Parse a GraphQL query string
///
/// This function parses a GraphQL query string and returns information about the
/// operation kind, name, and a unique query ID that can be used for SQL generation.
/// It also returns a resolution request with field paths for schema resolution.
#[rustler::nif]
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
    if let Some(cached_query_info) = get_from_cache(&query_id) {
        // Cache hit - return the cached parsed query info
        let operation_kind = atoms::operation_kind_to_atom(cached_query_info.operation_kind);

        // Create resolution request from cached query info
        let resolution_request = match create_resolution_request_from_cached(&cached_query_info) {
            Ok(req) => req,
            Err(e) => return Err(Error::Term(Box::new(e))),
        };

        // Convert resolution request to Elixir term
        let resolution_term = match convert_resolution_request_to_elixir(env, &resolution_request) {
            Ok(term) => term,
            Err(e) => return Err(e),
        };

        // Return the result with resolution request
        let result = (
            atoms::ok(),
            query_id.clone(),
            operation_kind,
            cached_query_info.operation_name.clone().unwrap_or_default(),
            resolution_term,
        );

        return Ok(result.encode(env));
    }

    // Parse the query
    let (parsed_query_info, resolution_request) = match parse_graphql(&query) {
        Ok((info, req)) => (info, req),
        Err(e) => return Err(Error::Term(Box::new(e))),
    };

    // Add to cache
    add_to_cache(&query_id, parsed_query_info.clone());

    // Return the operation info
    let operation_kind = atoms::operation_kind_to_atom(parsed_query_info.operation_kind);

    // Convert resolution request to Elixir term
    let resolution_term = match convert_resolution_request_to_elixir(env, &resolution_request) {
        Ok(term) => term,
        Err(e) => return Err(e),
    };

    // Return the result with resolution request
    let result = (
        atoms::ok(),
        query_id,
        operation_kind,
        parsed_query_info.operation_name.unwrap_or_default(),
        resolution_term,
    );

    Ok(result.encode(env))
}

/// Convert ResolutionRequest to Elixir terms
#[inline(always)]
fn convert_resolution_request_to_elixir<'a>(
    env: Env<'a>,
    request: &ResolutionRequest,
) -> NifResult<Term<'a>> {
    // Convert HashSet to Vec before encoding
    let field_paths_vec: Vec<Vec<u32>> = request.field_paths.iter().cloned().collect();

    // Create a tuple of {:field_names, field_names, :field_paths, field_paths}
    let result = (
        atoms::field_names(),
        request.field_names.clone(),
        atoms::field_paths(),
        field_paths_vec,
    )
        .encode(env);

    Ok(result)
}

/// Create a resolution request from a cached CachedQueryInfo
#[inline(always)]
fn create_resolution_request_from_cached(
    cached_info: &CachedQueryInfo,
) -> Result<ResolutionRequest, String> {
    // This function extracts field paths from a cached CachedQueryInfo
    // and creates a new ResolutionRequest for Elixir

    let field_paths = match &cached_info.field_paths {
        Some(paths) => paths,
        None => return Err("Field paths not found in cached query".to_string()),
    };

    // Get all interned strings and create a mapping from SymbolId to index
    let field_names = get_all_strings();
    let mut symbol_to_index = HashMap::with_capacity(field_names.len());

    for (i, name) in field_names.iter().enumerate() {
        let symbol_id = intern_str(name);
        symbol_to_index.insert(symbol_id, i as u32);
    }

    // Convert FieldPaths with SymbolIds to indices for Elixir
    let converted_paths = convert_paths_to_indices(field_paths, &symbol_to_index);

    Ok(ResolutionRequest {
        field_names,
        field_paths: converted_paths,
    })
}

/// Generate SQL from a parsed GraphQL query
///
/// This function generates SQL from a previously parsed GraphQL query,
/// identified by its query ID. It also takes variables that can be used
/// in the query.
#[rustler::nif]
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
    let cached_query_info = match get_from_cache(&query_id) {
        Some(info) => info,
        None => return Err(Error::Term(Box::new("Query not found in cache"))),
    };

    // Generate SQL using the cached query info
    // Note: We no longer have access to ast_context and document fields,
    // but we don't need them for SQL generation at this point
    let sql = generate_sql(&cached_query_info);

    // Create an empty list for parameters
    let params: Vec<Term<'a>> = Vec::new();

    Ok((atoms::ok(), sql, params).encode(env))
}
