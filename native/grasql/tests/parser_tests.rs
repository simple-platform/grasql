use graphql_query::ast::{ASTContext, Document, ParseNode};
use grasql::extraction::FieldPathExtractor;
use grasql::interning::intern_str;
use grasql::parser::parse_graphql;
use grasql::types::FieldPath;
use std::collections::HashSet;

// Helper function to ensure GraSQL is initialized before running tests
fn initialize_grasql() {
    // Ignore errors if already initialized
    let _ = grasql::types::initialize_for_test();
}

// Test helper to create a FieldPath from string segments
fn create_path(segments: &[&str]) -> FieldPath {
    let mut path = FieldPath::new();
    for &segment in segments {
        path.push(intern_str(segment));
    }
    path
}

// Test helper to parse a query and extract field paths
fn extract_field_paths(query: &str) -> HashSet<FieldPath> {
    let ctx = ASTContext::new();
    let document = Document::parse(&ctx, query).unwrap();
    let mut extractor = FieldPathExtractor::new();
    // Extract only the field paths component from the tuple
    let (field_paths, _) = extractor.extract(&document).unwrap();
    field_paths
}

// Test helper to check if a specific path exists in the extracted paths
fn assert_path_exists(paths: &HashSet<FieldPath>, segments: &[&str]) {
    let path = create_path(segments);
    assert!(
        paths.contains(&path),
        "Expected path {:?} not found in extracted paths",
        segments
    );
}

#[test]
fn test_deeply_nested_query() {
    // Initialize GraSQL config
    initialize_grasql();

    let query = r#"
    {
        users {
            id
            profile {
                avatar
                settings {
                    theme
                    notifications {
                        email
                        push {
                            enabled
                            frequency
                        }
                    }
                }
            }
            posts {
                id
                comments {
                    id
                    replies {
                        id
                        author {
                            id
                            name
                        }
                    }
                }
            }
        }
    }
    "#;

    let paths = extract_field_paths(query);

    // Test for all expected paths
    assert_path_exists(&paths, &["users"]);
    assert_path_exists(&paths, &["users", "profile"]);
    assert_path_exists(&paths, &["users", "profile", "settings"]);
    assert_path_exists(&paths, &["users", "profile", "settings", "notifications"]);
    assert_path_exists(
        &paths,
        &["users", "profile", "settings", "notifications", "push"],
    );
    assert_path_exists(&paths, &["users", "posts"]);
    assert_path_exists(&paths, &["users", "posts", "comments"]);
    assert_path_exists(&paths, &["users", "posts", "comments", "replies"]);
    assert_path_exists(&paths, &["users", "posts", "comments", "replies", "author"]);
}

#[test]
fn test_complex_filters() {
    // Initialize GraSQL config
    initialize_grasql();

    let query = r#"
    {
        users(where: {
            _and: [
                { name: { _like: "%John%" } },
                { email: { _ilike: "%example.com" } },
                { 
                    _or: [
                        { age: { _gt: 18 } },
                        { status: { _eq: "ACTIVE" } }
                    ]
                },
                {
                    profile: {
                        _and: [
                            { verified: { _eq: true } },
                            { 
                                location: { 
                                    city: { _eq: "New York" }
                                }
                            }
                        ]
                    }
                },
                {
                    posts: {
                        _in: [1, 2, 3]
                    }
                },
                {
                    posts: {
                        published: { _eq: true },
                        comments: {
                            content: { _like: "%Great%" }
                        }
                    }
                }
            ]
        }) {
            id
            name
        }
    }
    "#;

    let paths = extract_field_paths(query);

    // Test for expected table/relationship paths in filters
    assert_path_exists(&paths, &["users"]);
    assert_path_exists(&paths, &["users", "profile"]);
    assert_path_exists(&paths, &["users", "profile", "location"]);
    assert_path_exists(&paths, &["users", "posts"]);
    assert_path_exists(&paths, &["users", "posts", "comments"]);
}

#[test]
fn test_aggregations() {
    // Initialize GraSQL config
    initialize_grasql();

    let query = r#"
    {
        users_aggregate {
            aggregate {
                count
                sum {
                    age
                    score
                }
                avg {
                    age
                }
                max {
                    age
                }
                min {
                    age
                }
            }
            nodes {
                id
                name
            }
        }
        posts_aggregate(where: { author: { name: { _eq: "John" } } }) {
            aggregate {
                count
            }
        }
    }
    "#;

    let paths = extract_field_paths(query);

    // Test for expected aggregation paths
    assert_path_exists(&paths, &["users_aggregate"]);
    assert_path_exists(&paths, &["posts_aggregate"]);
    assert_path_exists(&paths, &["posts_aggregate", "author"]);
}

#[test]
fn test_pagination_and_sorting() {
    // Initialize GraSQL config
    initialize_grasql();

    let query = r#"
    {
        users(
            limit: 10, 
            offset: 20, 
            order_by: { name: asc, created_at: desc }
        ) {
            id
            name
        }
        posts(
            limit: 5,
            order_by: [
                { published_date: desc },
                { title: asc }
            ]
        ) {
            id
            title
        }
    }
    "#;

    let paths = extract_field_paths(query);

    // Test for expected paths
    assert_path_exists(&paths, &["users"]);
    assert_path_exists(&paths, &["posts"]);
}

#[test]
fn test_combined_features() {
    // Initialize GraSQL config
    initialize_grasql();

    let query = r#"
    {
        users(
            where: { 
                posts: { 
                    comments_aggregate: { 
                        aggregate: { 
                            count: { _gt: 5 }
                        }
                    }
                }
            },
            limit: 10,
            offset: 20,
            order_by: { name: asc }
        ) {
            id
            name
            posts(limit: 3, order_by: { created_at: desc }) {
                title
                comments_aggregate {
                    aggregate {
                        count
                    }
                }
            }
            profile {
                avatar
            }
        }
    }
    "#;

    let paths = extract_field_paths(query);

    // Test for expected paths
    assert_path_exists(&paths, &["users"]);
    assert_path_exists(&paths, &["users", "posts"]);
    assert_path_exists(&paths, &["users", "posts", "comments_aggregate"]);
    assert_path_exists(&paths, &["users", "profile"]);
}

#[test]
fn test_mutations() {
    // Initialize GraSQL config
    initialize_grasql();

    let query_insert = r#"
    mutation {
        insert_users(
            objects: [
                { name: "John", email: "john@example.com" },
                { name: "Jane", email: "jane@example.com" }
            ]
        ) {
            returning {
                id
                name
                profile {
                    avatar
                }
            }
            affected_rows
        }
        update_posts(
            where: { author_id: { _eq: 123 } },
            _set: { published: true }
        ) {
            returning {
                id
                title
            }
        }
    }
    "#;

    let paths = extract_field_paths(query_insert);

    // Test for expected paths
    assert_path_exists(&paths, &["insert_users"]);
    assert_path_exists(&paths, &["insert_users", "returning"]);
    assert_path_exists(&paths, &["insert_users", "returning", "profile"]);
    assert_path_exists(&paths, &["update_posts"]);
    assert_path_exists(&paths, &["update_posts", "returning"]);
}

#[test]
fn test_variables() {
    // Initialize GraSQL config
    initialize_grasql();

    let query = r#"
    query GetUsers($limit: Int!, $offset: Int, $filter: UserFilter) {
        users(
            limit: $limit,
            offset: $offset,
            where: $filter
        ) {
            id
            name
            email
        }
    }
    "#;

    let paths = extract_field_paths(query);

    // Test for expected paths
    assert_path_exists(&paths, &["users"]);
}

#[test]
fn test_aliases() {
    // Initialize GraSQL config
    initialize_grasql();

    let query = r#"
    {
        active_users: users(where: { status: { _eq: "ACTIVE" } }) {
            id
            full_name: name
            contact_info: profile {
                email
                phone
            }
            recent_posts: posts(limit: 5, order_by: { created_at: desc }) {
                id
                headline: title
            }
        }
    }
    "#;

    let paths = extract_field_paths(query);

    // Test for expected paths
    assert_path_exists(&paths, &["users"]);
    assert_path_exists(&paths, &["users", "profile"]);
    assert_path_exists(&paths, &["users", "posts"]);
}

#[test]
fn test_parse_graphql_function() {
    // Initialize GraSQL config
    initialize_grasql();

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

    // Test the full parse_graphql function
    let result = parse_graphql(query);
    assert!(result.is_ok(), "Failed to parse valid GraphQL query");

    let (info, request) = result.unwrap();
    assert_eq!(info.operation_kind, grasql::GraphQLOperationKind::Query);

    // Verify resolution request has expected field names
    assert!(request.strings.contains(&"users".to_string()));
    assert!(request.strings.contains(&"posts".to_string()));
}

#[test]
fn test_invalid_queries() {
    // Initialize GraSQL config
    initialize_grasql();

    // Test syntax error
    let invalid_query = "{ users { invalid syntax }";
    let result = parse_graphql(invalid_query);
    assert!(result.is_err());

    // Test empty document
    let empty_query = "";
    let result = parse_graphql(empty_query);
    assert!(result.is_err());
}

#[test]
fn test_resolution_request_format() {
    // Initialize GraSQL config
    initialize_grasql();

    // Query with various features to test the format
    let query = r#"
    query GetUsers {
        users(where: { active: true }) {
            id
            name
            posts {
                title
                content
            }
        }
    }
    "#;

    // Parse query and extract ResolutionRequest
    let (_, resolution_request) = parse_graphql(query).expect("Failed to parse query");

    // Verify query_id is present
    assert!(
        !resolution_request.query_id.is_empty(),
        "query_id should not be empty"
    );

    // Verify strings table is populated
    assert!(
        !resolution_request.strings.is_empty(),
        "strings table should not be empty"
    );

    // Check if expected strings are present
    let expected_strings = vec!["users", "id", "name", "posts", "title", "content", "active"];
    for expected in expected_strings {
        assert!(
            resolution_request.strings.iter().any(|s| s == expected),
            "strings table should contain '{}'",
            expected
        );
    }

    // Verify paths array is populated
    assert!(
        !resolution_request.paths.is_empty(),
        "paths array should not be empty"
    );

    // Verify path_dir is populated
    assert!(
        !resolution_request.path_dir.is_empty(),
        "path_dir should not be empty"
    );
    assert_eq!(
        resolution_request.path_dir.len(),
        resolution_request.path_types.len(),
        "path_dir and path_types should have the same length"
    );

    // Verify path_types is populated
    assert!(
        !resolution_request.path_types.is_empty(),
        "path_types should not be empty"
    );

    // Verify cols is populated
    assert!(
        !resolution_request.cols.is_empty(),
        "cols should not be empty"
    );

    // Verify ops is populated
    assert!(
        !resolution_request.ops.is_empty(),
        "ops should not be empty"
    );
    assert_eq!(
        resolution_request.ops.len(),
        1,
        "There should be one operation"
    );

    // Check operation type - should be query (0)
    let (_, op_type) = resolution_request.ops[0];
    assert_eq!(op_type, 0, "Operation type should be query (0)");
}

#[test]
fn test_resolution_request_caching() {
    // Initialize GraSQL config
    initialize_grasql();

    // Query to test caching
    let query = "{ users { id name } }";

    // First parse to populate cache
    let (info1, request1) = parse_graphql(query).expect("Failed to parse query 1");

    // Parse again - should hit cache
    let (info2, request2) = parse_graphql(query).expect("Failed to parse query 2");

    // Verify we got the same query_id
    assert_eq!(
        request1.query_id, request2.query_id,
        "query_id should be the same for identical queries"
    );

    // Verify operation kind is preserved
    assert_eq!(
        info1.operation_kind, info2.operation_kind,
        "operation_kind should be preserved in cache"
    );

    // We don't test exact structure matching as the strings table might
    // be affected by initialization or other tests. We should simply
    // verify that the query was parsed successfully both times.

    // Verify basic structure is present in both results
    assert!(
        !request1.strings.is_empty(),
        "First parse should have strings"
    );
    assert!(
        !request2.strings.is_empty(),
        "Second parse should have strings"
    );

    assert!(!request1.paths.is_empty(), "First parse should have paths");
    assert!(!request2.paths.is_empty(), "Second parse should have paths");

    // Verify that both requests contain the expected field names
    assert!(
        request1.strings.contains(&"users".to_string()),
        "First parse should contain 'users'"
    );
    assert!(
        request2.strings.contains(&"users".to_string()),
        "Second parse should contain 'users'"
    );
    assert!(
        request1.strings.contains(&"id".to_string()),
        "First parse should contain 'id'"
    );
    assert!(
        request2.strings.contains(&"id".to_string()),
        "Second parse should contain 'id'"
    );
    assert!(
        request1.strings.contains(&"name".to_string()),
        "First parse should contain 'name'"
    );
    assert!(
        request2.strings.contains(&"name".to_string()),
        "Second parse should contain 'name'"
    );
}

#[test]
fn test_mutation_operation_type() {
    // Initialize GraSQL config
    initialize_grasql();

    // Insert mutation query
    let insert_query =
        "mutation { insert_users(objects: [{name: \"test\"}]) { returning { id } } }";
    let (_, insert_request) = parse_graphql(insert_query).expect("Failed to parse insert mutation");

    // Check operation type
    assert!(!insert_request.ops.is_empty(), "ops should not be empty");
    let (_, insert_op_type) = insert_request.ops[0];
    assert_eq!(
        insert_op_type, 1,
        "Insert mutation should have operation type 1"
    );

    // Update mutation query
    let update_query = "mutation { update_users(where: {id: {_eq: 1}}, _set: {name: \"updated\"}) { returning { id } } }";
    let (_, update_request) = parse_graphql(update_query).expect("Failed to parse update mutation");

    // Check operation type
    assert!(!update_request.ops.is_empty(), "ops should not be empty");
    let (_, update_op_type) = update_request.ops[0];
    assert_eq!(
        update_op_type, 2,
        "Update mutation should have operation type 2"
    );

    // Delete mutation query
    let delete_query = "mutation { delete_users(where: {id: {_eq: 1}}) { returning { id } } }";
    let (_, delete_request) = parse_graphql(delete_query).expect("Failed to parse delete mutation");

    // Check operation type
    assert!(!delete_request.ops.is_empty(), "ops should not be empty");
    let (_, delete_op_type) = delete_request.ops[0];
    assert_eq!(
        delete_op_type, 3,
        "Delete mutation should have operation type 3"
    );
}

#[test]
fn test_multiple_operations() {
    // Initialize GraSQL config
    initialize_grasql();

    // Test each operation type individually first
    let query_operation = "query GetUsers { users { id name } }";
    let (_, query_request) =
        parse_graphql(query_operation).expect("Failed to parse query operation");
    assert_eq!(query_request.ops.len(), 1, "Should contain 1 operation");
    let (_, query_op_type) = query_request.ops[0];
    assert_eq!(query_op_type, 0, "Query operation should have type 0");

    let insert_operation = "mutation InsertPost { insert_posts(objects: [{title: \"New Post\"}]) { returning { id } } }";
    let (_, insert_request) =
        parse_graphql(insert_operation).expect("Failed to parse insert operation");
    assert_eq!(insert_request.ops.len(), 1, "Should contain 1 operation");
    let (_, insert_op_type) = insert_request.ops[0];
    assert_eq!(insert_op_type, 1, "Insert operation should have type 1");

    let update_operation = "mutation UpdateUser { update_users(where: {id: {_eq: 1}}, _set: {name: \"Updated\"}) { returning { id } } }";
    let (_, update_request) =
        parse_graphql(update_operation).expect("Failed to parse update operation");
    assert_eq!(update_request.ops.len(), 1, "Should contain 1 operation");
    let (_, update_op_type) = update_request.ops[0];
    assert_eq!(update_op_type, 2, "Update operation should have type 2");

    let delete_operation =
        "mutation DeleteComment { delete_comments(where: {id: {_eq: 5}}) { affected_rows } }";
    let (_, delete_request) =
        parse_graphql(delete_operation).expect("Failed to parse delete operation");
    assert_eq!(delete_request.ops.len(), 1, "Should contain 1 operation");
    let (_, delete_op_type) = delete_request.ops[0];
    assert_eq!(delete_op_type, 3, "Delete operation should have type 3");

    // Now test with multiple operations in one document
    // Note: In GraphQL, when using multiple operations in one document, each operation must be named,
    // and you must specify which operation to execute by name.
    let multi_op_query = r#"
    query GetUsers {
        users {
            id
            name
        }
    }

    mutation InsertPost {
        insert_posts(objects: [{title: "New Post", content: "Content here"}]) {
            returning {
                id
            }
        }
    }
    "#;

    // Parse the multi-operation document and assert success
    let (info, request) =
        parse_graphql(multi_op_query).expect("Failed to parse multi-operation document");

    // Verify operation info
    assert_eq!(
        info.operation_kind,
        grasql::GraphQLOperationKind::InsertMutation,
        "Primary operation kind should be InsertMutation"
    );

    // Since we have a named query, verify the operation name is preserved
    assert_eq!(
        info.operation_name,
        Some("GetUsers".to_string()),
        "Operation name should be GetUsers"
    );

    // Verify the resolution request contains both operations
    assert_eq!(request.ops.len(), 2, "Should contain exactly 2 operations");

    // Verify both "users" and "insert_posts" are in the strings table
    assert!(
        request.strings.contains(&"users".to_string()),
        "Strings table should contain 'users'"
    );
    assert!(
        request.strings.contains(&"insert_posts".to_string()),
        "Strings table should contain 'insert_posts'"
    );

    // Find the operations in the ops vector and verify correct types
    let mut found_query = false;
    let mut found_insert = false;

    for (field_idx, op_type) in &request.ops {
        let field_name = &request.strings[*field_idx as usize];

        if field_name == "users" {
            assert_eq!(*op_type, 0, "User operation should have type 0 (query)");
            found_query = true;
        } else if field_name == "insert_posts" {
            assert_eq!(
                *op_type, 1,
                "Insert_posts operation should have type 1 (insert mutation)"
            );
            found_insert = true;
        }
    }

    assert!(found_query, "Should contain a query operation for 'users'");
    assert!(
        found_insert,
        "Should contain an insert mutation operation for 'insert_posts'"
    );

    // Verify field paths exist for both operations
    assert!(!request.paths.is_empty(), "Paths should not be empty");
    assert!(
        !request.path_dir.is_empty(),
        "Path directory should not be empty"
    );
    assert!(
        !request.path_types.is_empty(),
        "Path types should not be empty"
    );

    // Verify document pointer is preserved
    assert!(
        info.document_ptr.is_some(),
        "Document pointer should be preserved for caching"
    );
}
