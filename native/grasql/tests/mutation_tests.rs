use graphql_query::ast::{ASTContext, Document, ParseNode};
use grasql::interning::intern_str;
use grasql::types::FieldPath;

/// Helper function to initialize GraSQL for tests
fn initialize_grasql() {
    let _ = grasql::types::initialize_for_test();
}

/// Helper function to create a path from string segments
fn create_path(segments: &[&str]) -> FieldPath {
    let mut path = FieldPath::new();
    for &segment in segments {
        path.push(intern_str(segment));
    }
    path
}

#[test]
fn test_insert_mutation_extraction() {
    // Initialize GraSQL config
    initialize_grasql();

    // Create a test INSERT mutation
    let query = r#"
    mutation {
        insert_users(objects: {
            name: "John",
            email: "john@example.com",
            profile: {
                bio: "Developer",
                website: "example.com"
            }
        }) {
            returning {
                id
                name
            }
        }
    }
    "#;

    // Extract field paths and column usage
    let mut extractor = grasql::extraction::FieldPathExtractor::new();
    let ctx = ASTContext::new();
    let document = Document::parse(&ctx, query).unwrap();
    let (_, column_usage) = extractor.extract(&document).unwrap();

    // Find users table path
    let users_path = create_path(&["insert_users"]);

    // Verify column extraction
    let columns = column_usage.get(&users_path).unwrap();
    assert!(columns.contains(&intern_str("name")));
    assert!(columns.contains(&intern_str("email")));
    assert!(columns.contains(&intern_str("profile")));

    // Test could also verify nested fields if needed
}

#[test]
fn test_insert_with_object_param() {
    // Initialize GraSQL config
    initialize_grasql();

    // Create a test INSERT mutation with object parameter
    let query = r#"
    mutation {
        insert_user(object: {
            name: "John",
            email: "john@example.com"
        }) {
            returning {
                id
            }
        }
    }
    "#;

    // Extract field paths and column usage
    let mut extractor = grasql::extraction::FieldPathExtractor::new();
    let ctx = ASTContext::new();
    let document = Document::parse(&ctx, query).unwrap();
    let (_, column_usage) = extractor.extract(&document).unwrap();

    // Find user table path
    let user_path = create_path(&["insert_user"]);

    // Verify column extraction
    let columns = column_usage.get(&user_path).unwrap();
    assert!(columns.contains(&intern_str("name")));
    assert!(columns.contains(&intern_str("email")));
}

#[test]
fn test_insert_with_variable() {
    // Initialize GraSQL config
    initialize_grasql();

    // Create a test INSERT mutation with variable
    let query = r#"
    mutation InsertUser($userData: UserInput!) {
        insert_user(object: $userData) {
            returning {
                id
            }
        }
    }
    "#;

    // Extract field paths and column usage
    let mut extractor = grasql::extraction::FieldPathExtractor::new();
    let ctx = ASTContext::new();
    let document = Document::parse(&ctx, query).unwrap();

    // We need to ensure the path is added to field_paths even if no columns
    // are extracted from the variable (since we're just trusting the user)
    let (field_paths, _) = extractor.extract(&document).unwrap();

    // Find user table path
    let user_path = create_path(&["insert_user"]);

    // Just verify that the path exists in field_paths
    assert!(field_paths.contains(&user_path));
}

#[test]
fn test_update_mutation_extraction() {
    // Initialize GraSQL config
    initialize_grasql();

    // Create a test UPDATE mutation
    let query = r#"
    mutation {
        update_users(
            where: { id: { _eq: 1 } },
            _set: {
                name: "Updated Name",
                email: "updated@example.com",
                status: "active"
            }
        ) {
            returning {
                id
                name
            }
        }
    }
    "#;

    // Extract field paths and column usage
    let mut extractor = grasql::extraction::FieldPathExtractor::new();
    let ctx = ASTContext::new();
    let document = Document::parse(&ctx, query).unwrap();
    let (_, column_usage) = extractor.extract(&document).unwrap();

    // Find users table path
    let users_path = create_path(&["update_users"]);

    // Verify column extraction
    let columns = column_usage.get(&users_path).unwrap();
    assert!(columns.contains(&intern_str("name")));
    assert!(columns.contains(&intern_str("email")));
    assert!(columns.contains(&intern_str("status")));
    // We'll add an additional test for the "id" column later since it's
    // part of a separate task to properly extract columns from the "where" condition
}

#[test]
fn test_batch_insert_extraction() {
    // Initialize GraSQL config
    initialize_grasql();

    // Create a test batch INSERT mutation
    let query = r#"
    mutation {
        insert_users(objects: [
            {
                name: "User 1",
                email: "user1@example.com"
            },
            {
                name: "User 2",
                email: "user2@example.com",
                phone: "123-456-7890"
            },
            {
                name: "User 3",
                status: "active"
            }
        ]) {
            returning {
                id
                name
            }
        }
    }
    "#;

    // Extract field paths and column usage
    let mut extractor = grasql::extraction::FieldPathExtractor::new();
    let ctx = ASTContext::new();
    let document = Document::parse(&ctx, query).unwrap();
    let (_, column_usage) = extractor.extract(&document).unwrap();

    // Find users table path
    let users_path = create_path(&["insert_users"]);

    // Verify column extraction - should include all unique fields from all objects
    let columns = column_usage.get(&users_path).unwrap();
    assert!(columns.contains(&intern_str("name")));
    assert!(columns.contains(&intern_str("email")));
    assert!(columns.contains(&intern_str("phone")));
    assert!(columns.contains(&intern_str("status")));
}
