/// NIF interface module for GraSQL
///
/// This module provides the NIFs (Native Implemented Functions) that are exposed to Elixir.
/// These functions are the bridge between Elixir and the Rust implementation of GraSQL.
use crate::atoms;
use crate::cache::{add_to_cache_with_request, generate_query_id, get_from_cache};
use crate::config::CONFIG;
use crate::parser::parse_graphql;
use crate::types::ResolutionRequest;

use rustler::{Encoder, Env, Error, NifResult, Term};

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

        // Use cached ResolutionRequest - it should always be available
        let resolution_request = match &cached_query_info.resolution_request {
            Some(req) => req.clone(),
            None => {
                return Err(Error::Term(Box::new(
                    "ResolutionRequest not found in cache - this should never happen",
                )))
            }
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

    // Add to cache with resolution request
    add_to_cache_with_request(
        &query_id,
        parsed_query_info.clone(),
        resolution_request.clone(),
    );

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
    // Create a map with atom keys for each field in the ResolutionRequest
    // This will be easier to pattern match in Elixir
    // Create individual terms
    let query_id_atom = atoms::query_id().encode(env);
    let query_id_term = request.query_id.encode(env);

    let strings_atom = atoms::field_names().encode(env); // Reuse field_names atom for strings
    let strings_term = request.strings.encode(env);

    let paths_atom = atoms::field_paths().encode(env); // Reuse field_paths atom for paths
    let paths_term = request.paths.encode(env);

    let path_dir_atom = atoms::path_dir().encode(env);
    let path_dir_term = request.path_dir.encode(env);

    let path_types_atom = atoms::path_types().encode(env);
    let path_types_term = request.path_types.encode(env);

    let cols_atom = atoms::column_map().encode(env); // Reuse column_map atom for cols
    let cols_term = request.cols.encode(env);

    let ops_atom = atoms::operations().encode(env);
    let ops_term = request.ops.encode(env);

    // Create a 14-element tuple with key-value pairs
    Ok(rustler::types::tuple::make_tuple(
        env,
        &[
            query_id_atom,
            query_id_term,
            strings_atom,
            strings_term,
            paths_atom,
            paths_term,
            path_dir_atom,
            path_dir_term,
            path_types_atom,
            path_types_term,
            cols_atom,
            cols_term,
            ops_atom,
            ops_term,
        ],
    ))
}

/// Generate SQL from a parsed GraphQL query
///
/// This function generates SQL from a previously parsed GraphQL query,
/// identified by its query ID. It also takes variables that can be used
/// in the query and resolved schema information.
#[rustler::nif]
pub fn do_generate_sql<'a>(
    env: Env<'a>,
    resolution_response: Term<'a>,
) -> rustler::NifResult<Term<'a>> {
    // Get the current configuration
    let _config = match CONFIG.lock() {
        Ok(cfg) => match &*cfg {
            Some(c) => c.clone(),
            None => return Err(Error::Term(Box::new("GraSQL not initialized"))),
        },
        Err(_) => return Err(Error::Term(Box::new("Failed to acquire config lock"))),
    };

    // Decode ResolutionResponse from Elixir term
    let response = decode_resolution_response(env, resolution_response)?;

    // Generate SQL using the cached query info and resolution response
    // Note: This is a stub implementation - will be replaced in Phase 3
    let _ = response; // Use the response to avoid unused variable warning

    // Create an empty list for parameters
    let params: Vec<Term<'a>> = Vec::new();

    Ok((atoms::ok(), "SELECT 1", params).encode(env))
}

/// Decode ResolutionResponse from Elixir term
fn decode_resolution_response<'a>(
    env: Env<'a>,
    term: Term<'a>,
) -> NifResult<crate::types::ResolutionResponse> {
    // Extract fields from the map
    let query_id: String = term.map_get(atoms::query_id())?.decode()?;
    let strings: Vec<String> = term
        .map_get(&rustler::types::atom::Atom::from_str(env, "strings")?)?
        .decode()?;
    let tables: Vec<(u32, u32, u32)> = term
        .map_get(&rustler::types::atom::Atom::from_str(env, "tables")?)?
        .decode()?;

    // Decode relationships with source and target column arrays
    let rels: Vec<(u32, u32, u8, i32, Vec<u32>, Vec<u32>)> = term
        .map_get(&rustler::types::atom::Atom::from_str(env, "rels")?)?
        .decode()?;

    let joins: Vec<(u32, u32, Vec<u32>, Vec<u32>)> = term
        .map_get(&rustler::types::atom::Atom::from_str(env, "joins")?)?
        .decode()?;
    let path_map: Vec<(u8, u32)> = term
        .map_get(&rustler::types::atom::Atom::from_str(env, "path_map")?)?
        .decode()?;
    let cols: Vec<(u32, u32, u32, i32)> = term
        .map_get(&rustler::types::atom::Atom::from_str(env, "cols")?)?
        .decode()?;

    // Decode operations
    let ops: Vec<(u32, u8)> = term
        .map_get(&rustler::types::atom::Atom::from_str(env, "ops")?)?
        .decode()?;

    Ok(crate::types::ResolutionResponse {
        query_id,
        strings,
        tables,
        rels,
        joins,
        path_map,
        cols,
        ops,
    })
}
