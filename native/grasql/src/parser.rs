/// GraphQL parsing module
///
/// This module provides functionality for parsing GraphQL queries and
/// extracting necessary information for SQL generation.
use crate::extraction::{build_path_index, convert_paths_to_indices, FieldPathExtractor};
use crate::interning::{get_all_strings, intern_str};
use crate::types::{GraphQLOperationKind, ParsedQueryInfo, ResolutionRequest};
use graphql_query::ast::{ASTContext, Definition, Document, Field, ParseNode, Selection};
use std::collections::HashMap;
use std::sync::Arc;

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

    // Extract operation information
    let mut operation_kind = GraphQLOperationKind::Query; // Default to query
    let mut operation_name = None;

    // Find the first operation definition
    for definition in document.definitions.iter() {
        if let Definition::Operation(op) = definition {
            operation_kind = op.operation.into();

            if let Some(name) = &op.name {
                operation_name = Some(name.name.to_string());
            }

            // For simplicity, we just use the first operation
            break;
        }
    }

    // Extract field paths
    let mut extractor = FieldPathExtractor::new();
    let field_paths = match extractor.extract(&document) {
        Ok(paths) => paths,
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

    // Create parsed query info with extracted data
    let parsed_query_info = ParsedQueryInfo {
        operation_kind,
        operation_name,
        field_paths: Some(field_paths.clone()),
        path_index: Some(build_path_index(&field_paths)),
        ast_context: Some(Arc::new(ctx)),
        document: None, // We can't easily store the document with 'static lifetime
    };

    // Create resolution request
    let resolution_request = ResolutionRequest {
        field_names,
        field_paths: converted_paths,
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
