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

    // Convert HashMap<u32, HashSet<String>> to Vec<(u32, Vec<String>)> for encoding
    let column_map_vec: Vec<(u32, Vec<String>)> = request
        .column_map
        .iter()
        .map(|(&table_idx, columns)| (table_idx, columns.iter().cloned().collect::<Vec<String>>()))
        .collect();

    // Get operation kind atom
    let op_kind_atom = atoms::operation_kind_to_atom(request.operation_kind);

    // Create individual terms
    let field_names_atom = atoms::field_names().encode(env);
    let field_names_term = request.field_names.encode(env);
    let field_paths_atom = atoms::field_paths().encode(env);
    let field_paths_term = field_paths_vec.encode(env);
    let column_map_atom = atoms::column_map().encode(env);
    let column_map_term = column_map_vec.encode(env);
    let operation_kind_atom = atoms::operation_kind().encode(env);
    let operation_kind_term = op_kind_atom.encode(env);

    // Create an 8-element tuple
    Ok(rustler::types::tuple::make_tuple(
        env,
        &[
            field_names_atom,
            field_names_term,
            field_paths_atom,
            field_paths_term,
            column_map_atom,
            column_map_term,
            operation_kind_atom,
            operation_kind_term,
        ],
    ))
}

/// Create a resolution request from a cached CachedQueryInfo
#[inline(always)]
fn create_resolution_request_from_cached(
    cached_info: &CachedQueryInfo,
) -> Result<ResolutionRequest, String> {
    // Extract field paths from a cached CachedQueryInfo
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

    // Extract column usage from cached query info
    let column_map = match &cached_info.column_usage {
        Some(column_usage) => {
            // Convert column usage to table indices with column strings
            crate::extraction::convert_column_usage_to_indices(
                column_usage,
                field_paths,
                &symbol_to_index,
            )
        }
        None => HashMap::new(), // Default empty column map if no column usage info
    };

    Ok(ResolutionRequest {
        field_names,
        field_paths: converted_paths,
        column_map,
        operation_kind: cached_info.operation_kind,
    })
}

/// Generate SQL from a parsed GraphQL query
///
/// This function generates SQL from a previously parsed GraphQL query,
/// identified by its query ID. It also takes variables that can be used
/// in the query and resolved schema information.
#[rustler::nif]
pub fn do_generate_sql<'a>(
    env: Env<'a>,
    query_id: String,
    _variables: Term<'a>,
    _schema: Term<'a>,
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
    // Note: We're not using the schema parameter yet - this will be implemented in Phase 3
    // For now, we just store the schema information and pass it along
    let sql = generate_sql(&cached_query_info);

    // Create an empty list for parameters
    let params: Vec<Term<'a>> = Vec::new();

    Ok((atoms::ok(), sql, params).encode(env))
}
