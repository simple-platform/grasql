/// GraphQL parsing module
///
/// This module provides functionality for parsing GraphQL queries and
/// extracting necessary information for SQL generation.
use crate::cache::generate_query_id;
use crate::extraction::{build_path_index, FieldPathExtractor};
use crate::interning::{get_all_strings, intern_str};
use crate::types::{GraphQLOperationKind, ParsedQueryInfo, ResolutionRequest};
use graphql_query::ast::{ASTContext, Definition, Document, Field, ParseNode, Selection};
use std::collections::HashMap;
use std::mem;
use std::sync::Arc;

/// Determine the specific operation kind, including mutation type
#[inline(always)]
fn determine_operation_kind(document: &Document) -> Result<GraphQLOperationKind, String> {
    // Find all operation definitions and determine the primary operation kind
    let mut has_operation = false;
    let mut primary_kind = GraphQLOperationKind::Query; // Default to query

    for definition in document.definitions.iter() {
        if let Definition::Operation(op) = definition {
            has_operation = true;

            // If it's a mutation, determine specific type
            if let graphql_query::ast::OperationKind::Mutation = op.operation {
                // Check if we have selections first
                if op.selection_set.selections.is_empty() {
                    continue; // Skip empty operations
                }

                // Look at first selection name to determine mutation type
                if let Some(selection) = op.selection_set.selections.first() {
                    if let Some(field) = selection.field() {
                        // Get the current configuration to access prefixes
                        let config = match crate::config::CONFIG.lock() {
                            Ok(cfg) => match &*cfg {
                                Some(c) => c.clone(),
                                None => return Ok(GraphQLOperationKind::InsertMutation), // Default if not initialized
                            },
                            Err(_) => return Ok(GraphQLOperationKind::InsertMutation), // Default if lock fails
                        };

                        // Check field name against configured prefixes
                        let field_name = field.name;
                        if field_name.starts_with(&config.insert_prefix) {
                            primary_kind = GraphQLOperationKind::InsertMutation;
                        } else if field_name.starts_with(&config.update_prefix) {
                            primary_kind = GraphQLOperationKind::UpdateMutation;
                        } else if field_name.starts_with(&config.delete_prefix) {
                            primary_kind = GraphQLOperationKind::DeleteMutation;
                        } else {
                            primary_kind = GraphQLOperationKind::InsertMutation;
                            // Default
                        }
                    }
                }
            } else {
                // For non-mutation operations, convert directly
                let kind = op.operation.into();

                // If we find a mutation, prioritize it over query/subscription
                if matches!(
                    kind,
                    GraphQLOperationKind::InsertMutation
                        | GraphQLOperationKind::UpdateMutation
                        | GraphQLOperationKind::DeleteMutation
                ) {
                    primary_kind = kind;
                } else if primary_kind == GraphQLOperationKind::Query {
                    // Only update if we haven't found a mutation yet
                    primary_kind = kind;
                }
            }
        }
    }

    if !has_operation {
        return Err(String::from("No operations found in document"));
    }

    Ok(primary_kind)
}

/// Parse a GraphQL query string and extract necessary information
///
/// This function parses a GraphQL query string and extracts operation information
/// such as the operation kind (query, mutation, subscription) and name.
/// It also extracts field paths for tables and relationships needed for schema resolution.
///
/// Note: This parser does not support GraphQL fragments or directives.
#[inline(always)]
pub fn parse_graphql(query: &str) -> Result<(ParsedQueryInfo, ResolutionRequest), String> {
    // Create a new AST context
    let ctx = ASTContext::new();

    // Generate query ID for caching
    let query_id = generate_query_id(query);

    // Parse the query using the ParseNode trait
    let document = match Document::parse(&ctx, query) {
        Ok(doc) => doc,
        Err(e) => return Err(format!("Failed to parse GraphQL query: {}", e)),
    };

    // Check for unsupported features: fragments and directives
    for definition in document.definitions.iter() {
        // Check for fragment definitions
        if let Definition::Fragment(_) = definition {
            return Err(String::from("GraphQL fragments are not supported"));
        }

        // Check for directive usage in operations
        if let Definition::Operation(op) = definition {
            if !op.directives.is_empty() {
                return Err(String::from("GraphQL directives are not supported"));
            }

            // Check for directives and fragments in the selection set
            for selection in op.selection_set.selections.iter() {
                match selection {
                    // FragmentSpread is not supported
                    Selection::FragmentSpread(_) => {
                        return Err(String::from("GraphQL fragment spreads are not supported"));
                    }
                    // InlineFragment is not supported
                    Selection::InlineFragment(_) => {
                        return Err(String::from("GraphQL inline fragments are not supported"));
                    }
                    // Check if fields have directives
                    Selection::Field(field) => {
                        if !field.directives.is_empty() {
                            return Err(String::from("GraphQL directives are not supported"));
                        }

                        // Recursively check for directives and fragments in nested fields
                        if let Err(e) = check_field_for_unsupported_features(field) {
                            return Err(e);
                        }
                    }
                }
            }
        }
    }

    // Determine operation kind (now with specific mutation types)
    let operation_kind = determine_operation_kind(&document)?;

    // Extract operation name
    let mut operation_name = None;

    // Find the first operation definition
    for definition in document.definitions.iter() {
        if let Definition::Operation(op) = definition {
            if let Some(name) = &op.name {
                operation_name = Some(name.name.to_string());
            }
            break;
        }
    }

    // Extract field paths and column usage
    let mut extractor = FieldPathExtractor::new();
    let (field_paths, column_usage) = match extractor.extract(&document) {
        Ok(result) => result,
        Err(e) => return Err(e),
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

    // Encode each field path
    for (_path_id, path) in field_paths.iter().enumerate() {
        // Record the current offset in the paths array
        path_dir.push(paths.len() as u32);

        // Add the path length
        paths.push(path.len() as u32);

        // Add each path segment as an index into the strings array
        for &symbol_id in path.iter() {
            let idx = *symbol_to_index
                .get(&symbol_id)
                .expect("Symbol not found in mapping");
            paths.push(idx);
        }

        // Determine if this is a table (0) or relationship (1)
        // Heuristic: paths of length 1 are tables, longer paths are relationships
        let path_type = if path.len() == 1 { 0 } else { 1 };
        path_types.push(path_type);
    }

    // Convert column_usage to the new cols format
    let mut cols = Vec::new();
    for path in field_paths.iter() {
        // Skip paths that aren't tables (no columns)
        if path.len() != 1 {
            continue;
        }

        // Get the table index (first element of path)
        let table_idx = *symbol_to_index
            .get(&path[0])
            .expect("Symbol not found in mapping");

        // Check if there are columns for this table
        if let Some(columns) = column_usage.get(path) {
            // Convert column SymbolIds to indices
            let column_indices: Vec<u32> = columns
                .iter()
                .map(|&symbol_id| {
                    *symbol_to_index
                        .get(&symbol_id)
                        .expect("Column symbol not found in mapping")
                })
                .collect();

            // Only add if there are columns to resolve
            if !column_indices.is_empty() {
                cols.push((table_idx, column_indices));
            }
        }
    }

    // Extract operations
    let mut ops = Vec::new();
    for definition in document.definitions.iter() {
        if let Definition::Operation(op) = definition {
            // For each operation, add the root fields
            for selection in op.selection_set.selections.iter() {
                if let Selection::Field(field) = selection {
                    let field_idx = *symbol_to_index
                        .get(&intern_str(field.name))
                        .expect("Field not found in mapping");

                    // Get the current configuration for operation prefixes
                    let config = match crate::config::CONFIG.lock() {
                        Ok(cfg) => match &*cfg {
                            Some(c) => c.clone(),
                            None => return Err("GraSQL not initialized".to_string()),
                        },
                        Err(_) => return Err("Failed to acquire config lock".to_string()),
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

    // Save raw pointer to the document - will be valid as long as ctx is alive
    // This avoids re-parsing the document later
    let document_ptr = unsafe {
        // Safety: We're storing the document in the AST context's arena,
        // which is wrapped in an Arc, ensuring it lives as long as references to it.
        // We're extending the lifetime to 'static but we maintain the invariant that
        // the pointer is only dereferenced when the AST context is still alive.

        // Run several validation checks to ensure the document is valid
        debug_assert!(
            !document.definitions.is_empty(),
            "Document has no definitions, may be invalid"
        );

        // Validate that there's at least one valid operation
        let has_valid_operation = document.definitions.iter().any(|def| match def {
            Definition::Operation(op) => !op.selection_set.selections.is_empty(),
            _ => false,
        });

        debug_assert!(
            has_valid_operation,
            "Document has no valid operations with selections"
        );

        // Get the raw pointer to the Document
        let ptr = document as *const Document;
        debug_assert!(!ptr.is_null(), "Document pointer is null");

        // This lifetime transmutation is safe because:
        // 1. We only use this pointer with a valid ast_context reference
        // 2. The document's memory is owned by the ast_context arena
        // 3. We only perform immutable reads through this pointer
        // 4. The document() method performs extensive validation
        mem::transmute::<*const Document, *const Document<'static>>(ptr)
    };

    // Create AST context with Arc for thread-safety
    let ctx_arc = Arc::new(ctx);

    // Create parsed query info with extracted data
    let parsed_query_info = ParsedQueryInfo {
        operation_kind,
        operation_name,
        field_paths: Some(field_paths.clone()),
        path_index: Some(build_path_index(&field_paths)),
        ast_context: Some(ctx_arc),
        original_query: Some(query.to_string()),
        document_ptr: Some(document_ptr),
        column_usage: Some(column_usage),
        _phantom: std::marker::PhantomData,
    };

    // Create resolution request
    let resolution_request = ResolutionRequest {
        query_id: query_id.clone(),
        strings,
        paths,
        path_dir,
        path_types,
        cols,
        ops,
    };

    Ok((parsed_query_info, resolution_request))
}

/// Recursively check fields for unsupported features like directives and fragments
fn check_field_for_unsupported_features(field: &Field) -> Result<(), String> {
    // Check for nested selections
    for selection in field.selection_set.selections.iter() {
        match selection {
            // FragmentSpread is not supported
            Selection::FragmentSpread(_) => {
                return Err(String::from("GraphQL fragment spreads are not supported"));
            }
            // InlineFragment is not supported
            Selection::InlineFragment(_) => {
                return Err(String::from("GraphQL inline fragments are not supported"));
            }
            // Check if nested fields have directives
            Selection::Field(nested_field) => {
                if !nested_field.directives.is_empty() {
                    return Err(String::from("GraphQL directives are not supported"));
                }

                // Recursively check deeper nested fields
                check_field_for_unsupported_features(nested_field)?;
            }
        }
    }

    Ok(())
}
