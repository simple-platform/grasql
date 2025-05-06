/// GraphQL parsing module
///
/// This module provides functionality for parsing GraphQL queries and
/// extracting necessary information for SQL generation.
use crate::extraction::{build_path_index, convert_paths_to_indices, FieldPathExtractor};
use crate::interning::{get_all_strings, intern_str};
use crate::types::{GraphQLOperationKind, ParsedQueryInfo, ResolutionRequest};
use graphql_query::ast::{ASTContext, Definition, Document, Field, ParseNode, Selection};
use std::collections::HashMap;
use std::mem;
use std::sync::Arc;

/// Determine the specific operation kind, including mutation type
#[inline(always)]
fn determine_operation_kind(document: &Document) -> Result<GraphQLOperationKind, String> {
    // Find the operation first
    let operation = document
        .operation(None)
        .map_err(|e| format!("Error determining operation: {}", e))?;

    // If it's a mutation, determine specific type
    if let graphql_query::ast::OperationKind::Mutation = operation.operation {
        // Check if we have selections first
        if operation.selection_set.selections.is_empty() {
            return Err(String::from("Mutation has empty selection set"));
        }

        // Look at first selection name to determine mutation type
        if let Some(selection) = operation.selection_set.selections.first() {
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
                    return Ok(GraphQLOperationKind::InsertMutation);
                } else if field_name.starts_with(&config.update_prefix) {
                    return Ok(GraphQLOperationKind::UpdateMutation);
                } else if field_name.starts_with(&config.delete_prefix) {
                    return Ok(GraphQLOperationKind::DeleteMutation);
                }
            }
        }
        // Default to insert mutation if we can't determine type
        return Ok(GraphQLOperationKind::InsertMutation);
    }

    // For non-mutation operations, convert directly
    Ok(operation.operation.into())
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
    let field_names = get_all_strings();
    let mut symbol_to_index = HashMap::with_capacity(field_names.len());

    for (i, name) in field_names.iter().enumerate() {
        let symbol_id = intern_str(name);
        symbol_to_index.insert(symbol_id, i as u32);
    }

    // Convert FieldPaths with SymbolIds to indices for Elixir
    let converted_paths = convert_paths_to_indices(&field_paths, &symbol_to_index);

    // Convert column usage to table indices with column strings
    let column_map = crate::extraction::convert_column_usage_to_indices(
        &column_usage,
        &field_paths,
        &symbol_to_index,
    );

    // Save raw pointer to the document - will be valid as long as ctx is alive
    // This avoids re-parsing the document later
    let document_ptr = unsafe {
        // Safety: We're storing the document in the AST context's arena,
        // which is wrapped in an Arc, ensuring it lives as long as references to it.
        // We're extending the lifetime to 'static but we maintain the invariant that
        // the pointer is only dereferenced when the AST context is still alive.
        let ptr = document as *const Document;
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

    // Create resolution request with column map
    let resolution_request = ResolutionRequest {
        field_names,
        field_paths: converted_paths,
        column_map,
        operation_kind,
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
