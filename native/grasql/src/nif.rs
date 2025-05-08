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
use crate::types::{CachedQueryInfo, FieldPath, GraphQLOperationKind, ResolutionRequest};
use graphql_query::ast::{Definition, Document, Field, Selection};

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
        let resolution_request =
            match create_resolution_request_from_cached(&cached_query_info, query_id.clone()) {
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

/// Create a resolution request from a cached CachedQueryInfo
#[inline(always)]
fn create_resolution_request_from_cached(
    cached_info: &CachedQueryInfo,
    query_id: String,
) -> Result<ResolutionRequest, String> {
    // Extract document for parsing operations
    let document = match cached_info.document() {
        Some(doc) => doc,
        None => return Err("Document not found in cached query".to_string()),
    };

    // Extract field paths from a cached CachedQueryInfo
    let field_paths = match &cached_info.field_paths {
        Some(paths) => paths,
        None => return Err("Field paths not found in cached query".to_string()),
    };

    // Get all interned strings and create a mapping from SymbolId to index
    let strings = get_all_strings();
    let mut symbol_to_index = HashMap::with_capacity(strings.len());

    for (i, name) in strings.iter().enumerate() {
        let symbol_id = intern_str(name);
        symbol_to_index.insert(symbol_id, i as u32);
    }

    // Create the encoded paths, path directory, and path types arrays
    let mut paths = Vec::new();
    let mut path_dir = Vec::new();
    let mut path_types = Vec::new();

    // Sort field paths to ensure deterministic encoding
    let mut sorted_paths: Vec<&FieldPath> = field_paths.iter().collect();
    sorted_paths.sort_by_key(|p| {
        p.iter()
            .map(|&s| symbol_to_index.get(&s).copied().unwrap_or(0))
            .collect::<Vec<_>>()
    });

    // Encode each field path
    for (path_id, path) in sorted_paths.iter().enumerate() {
        // Record the current offset in the paths array
        path_dir.push(paths.len() as u32);

        // Add the path length
        paths.push(path.len() as u32);

        // Add each path segment as an index into the strings array
        for &symbol_id in path.iter() {
            let idx = match symbol_to_index.get(&symbol_id) {
                Some(&idx) => idx,
                None => return Err(format!("Symbol not found in mapping: {:?}", symbol_id)),
            };
            paths.push(idx);
        }

        // Determine if this is a table (0) or relationship (1)
        // Heuristic: paths of length 1 are tables, longer paths are relationships
        let path_type = if path.len() == 1 { 0 } else { 1 };
        path_types.push(path_type);
    }

    // Convert column_usage to the new cols format
    let mut cols = Vec::new();

    // Extract column usage from cached query info
    if let Some(column_usage) = &cached_info.column_usage {
        for path in sorted_paths.iter() {
            // Skip paths that aren't tables (no columns)
            if path.len() != 1 {
                continue;
            }

            // Get the table index (first element of path)
            let table_idx = match symbol_to_index.get(&path[0]) {
                Some(&idx) => idx,
                None => return Err(format!("Table symbol not found in mapping: {:?}", path[0])),
            };

            // Check if there are columns for this table
            if let Some(columns) = column_usage.get(path) {
                // Convert column SymbolIds to indices
                let column_indices: Vec<u32> = columns
                    .iter()
                    .filter_map(|&symbol_id| symbol_to_index.get(&symbol_id).copied())
                    .collect();

                // Only add if there are columns to resolve
                if !column_indices.is_empty() {
                    cols.push((table_idx, column_indices));
                }
            }
        }
    }

    // Get the current configuration for operation prefixes
    let config = match crate::config::CONFIG.lock() {
        Ok(cfg) => match &*cfg {
            Some(c) => c.clone(),
            None => return Err("GraSQL not initialized".to_string()),
        },
        Err(_) => return Err("Failed to acquire config lock".to_string()),
    };

    // Extract operations from document
    let mut ops = Vec::new();

    // Process each operation definition
    for definition in document.definitions.iter() {
        if let Definition::Operation(op) = definition {
            // For each operation, add the root fields
            for selection in op.selection_set.selections.iter() {
                if let Selection::Field(field) = selection {
                    let field_symbol = intern_str(field.name);
                    let field_idx = match symbol_to_index.get(&field_symbol) {
                        Some(&idx) => idx,
                        None => {
                            return Err(format!(
                                "Field symbol not found in mapping: {}",
                                field.name
                            ))
                        }
                    };

                    // Determine operation type based on operation kind and field name
                    let op_type = match op.operation {
                        graphql_query::ast::OperationKind::Query => 0,
                        graphql_query::ast::OperationKind::Mutation => {
                            // Check field name against configured prefixes to determine specific mutation type
                            if field.name.starts_with(&config.insert_prefix) {
                                1 // Insert mutation
                            } else if field.name.starts_with(&config.update_prefix) {
                                2 // Update mutation
                            } else if field.name.starts_with(&config.delete_prefix) {
                                3 // Delete mutation
                            } else {
                                // Default to insert if no prefix match
                                1
                            }
                        }
                        graphql_query::ast::OperationKind::Subscription => 4,
                    };

                    ops.push((field_idx, op_type));
                }
            }
        }
    }

    // Create resolution request
    Ok(ResolutionRequest {
        query_id,
        strings,
        paths,
        path_dir,
        path_types,
        cols,
        ops,
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
    _resolution_response: Term<'a>,
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
    // let cached_query_info = match get_from_cache(&resolution_response.query_id) {
    //     Some(info) => info,
    //     None => return Err(Error::Term(Box::new("Query not found in cache"))),
    // };

    // Generate SQL using the cached query info
    // Note: We're not using the schema parameter yet - this will be implemented in Phase 3
    // For now, we just store the schema information and pass it along
    // let sql = generate_sql(&cached_query_info);

    // Create an empty list for parameters
    let params: Vec<Term<'a>> = Vec::new();

    Ok((atoms::ok(), "SELECT 1", params).encode(env))
}
