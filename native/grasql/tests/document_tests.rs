use graphql_query::ast::{ASTContext, Document};
use grasql::parser::parse_graphql;
use grasql::types::{CachedQueryInfo, GraphQLOperationKind};
use std::mem::drop;
use std::sync::Arc;

// Helper function to ensure GraSQL is initialized before running tests
fn initialize_grasql() {
    // Ignore errors if already initialized
    let _ = grasql::types::initialize_for_test();
}

// Test helper to check if a document contains specific operation type and field
fn check_document_content(doc: &Document, expected_operation: GraphQLOperationKind) {
    // Find the operation
    let operation = doc.operation(None).expect("Failed to get operation");

    // Check operation kind
    let op_kind = GraphQLOperationKind::from(operation.operation);
    assert_eq!(op_kind, expected_operation, "Operation kind mismatch");

    // Check if there are fields in the selection set
    assert!(
        !operation.selection_set.is_empty(),
        "Selection set should not be empty"
    );
}

#[test]
fn test_basic_document_access() {
    // Initialize GraSQL config
    initialize_grasql();

    // Simple GraphQL query
    let query = r#"
    {
        users {
            id
            name
        }
    }
    "#;

    // Parse the query
    let result = parse_graphql(query);
    assert!(result.is_ok(), "Failed to parse valid GraphQL query");

    let (parsed_query_info, _) = result.unwrap();

    // Access the document
    let document = parsed_query_info.document();
    assert!(document.is_some(), "Document should be accessible");

    // Verify document content
    let doc = document.unwrap();
    check_document_content(doc, GraphQLOperationKind::Query);
}

#[test]
fn test_document_access_after_caching() {
    // Initialize GraSQL config
    initialize_grasql();

    // GraphQL query
    let query = r#"
    {
        users {
            id
            name
        }
    }
    "#;

    // Parse the query
    let result = parse_graphql(query);
    assert!(result.is_ok(), "Failed to parse valid GraphQL query");

    let (parsed_query_info, _) = result.unwrap();

    // Convert to CachedQueryInfo
    let cached_query_info = CachedQueryInfo::from(parsed_query_info);

    // Access the document from cached info
    let document = cached_query_info.document();
    assert!(
        document.is_some(),
        "Document should be accessible from cache"
    );

    // Verify document content
    let doc = document.unwrap();
    check_document_content(doc, GraphQLOperationKind::Query);
}

#[test]
fn test_document_access_with_reparse_fallback() {
    // Initialize GraSQL config
    initialize_grasql();

    // Create a query string
    let query = "{ users { id name } }";

    // Create an AST context
    let ctx = Arc::new(ASTContext::new());

    // Create a ParsedQueryInfo with no document_ptr but with original_query and ast_context
    let parsed_query_info = grasql::types::ParsedQueryInfo {
        operation_kind: GraphQLOperationKind::Query,
        operation_name: None,
        field_paths: None,
        path_index: None,
        ast_context: Some(ctx),
        original_query: Some(query.to_string()),
        document_ptr: None, // Force re-parsing
        column_usage: None,
        _phantom: std::marker::PhantomData,
    };

    // Access the document - should fall back to re-parsing
    let document = parsed_query_info.document();
    assert!(
        document.is_some(),
        "Document should be accessible through re-parsing"
    );

    // Verify document content
    let doc = document.unwrap();
    check_document_content(doc, GraphQLOperationKind::Query);
}

#[test]
fn test_memory_safety() {
    // Initialize GraSQL config
    initialize_grasql();

    // GraphQL query
    let query = r#"
    {
        users {
            id
            name
        }
    }
    "#;

    // Parse the query
    let result = parse_graphql(query);
    assert!(result.is_ok(), "Failed to parse valid GraphQL query");

    let (parsed_query_info, _) = result.unwrap();

    // Clone the ParsedQueryInfo
    let cloned_info = parsed_query_info.clone();

    // Drop the original
    drop(parsed_query_info);

    // Access the document from the clone
    let document = cloned_info.document();
    assert!(
        document.is_some(),
        "Document should be accessible from clone after original is dropped"
    );

    // Verify document content
    let doc = document.unwrap();
    check_document_content(doc, GraphQLOperationKind::Query);
}

#[test]
fn test_document_with_mutation_query() {
    // Initialize GraSQL config
    initialize_grasql();

    // Mutation query
    let query = r#"
    mutation {
        insert_users(objects: { name: "John", email: "john@example.com" }) {
            returning {
                id
                name
            }
        }
    }
    "#;

    // Parse the query
    let result = parse_graphql(query);
    assert!(result.is_ok(), "Failed to parse valid mutation query");

    let (parsed_query_info, _) = result.unwrap();

    // Check operation kind
    assert_eq!(
        parsed_query_info.operation_kind,
        GraphQLOperationKind::InsertMutation,
        "Should detect insert mutation"
    );

    // Access the document
    let document = parsed_query_info.document();
    assert!(document.is_some(), "Document should be accessible");

    // Convert to cache and verify document access still works
    let cached_query_info = CachedQueryInfo::from(parsed_query_info);
    let cached_document = cached_query_info.document();
    assert!(
        cached_document.is_some(),
        "Document should be accessible from cache"
    );
}

#[test]
fn test_multiple_document_accesses() {
    // Initialize GraSQL config
    initialize_grasql();

    // GraphQL query
    let query = r#"
    {
        users {
            id
            name
            posts {
                title
            }
        }
    }
    "#;

    // Parse the query
    let result = parse_graphql(query);
    assert!(result.is_ok(), "Failed to parse valid GraphQL query");

    let (parsed_query_info, _) = result.unwrap();

    // Access the document multiple times
    for _ in 0..5 {
        let document = parsed_query_info.document();
        assert!(
            document.is_some(),
            "Document should be accessible on each iteration"
        );

        // Verify some content to ensure the document is valid
        let doc = document.unwrap();
        let operation = doc.operation(None).expect("Failed to get operation");
        assert!(
            !operation.selection_set.is_empty(),
            "Selection set should not be empty"
        );
    }
}
