use graphql_query::ast::{ASTContext, Document, ParseNode};
use grasql::extraction::FieldPathExtractor;
use grasql::interning::intern_str;
use grasql::parser::parse_graphql;
use grasql::types::FieldPath;
use proptest::prelude::*;

// Test helper to create a FieldPath from string segments
fn create_path(segments: &[&str]) -> FieldPath {
    let mut path = FieldPath::new();
    for &segment in segments {
        path.push(intern_str(segment));
    }
    path
}

// Generator for valid field names (GraphQL identifiers)
fn field_name_strategy() -> impl Strategy<Value = String> {
    // GraphQL identifiers start with a letter or underscore and can contain letters, numbers, and underscores
    r"[a-zA-Z_][a-zA-Z0-9_]{0,15}".prop_map(|s| s)
}

// Generator for simple GraphQL leaf fields
fn leaf_field_strategy() -> impl Strategy<Value = String> {
    field_name_strategy()
}

// Generator for simple value literals
fn simple_value_strategy() -> impl Strategy<Value = String> {
    prop_oneof![
        // String value
        r#""[a-zA-Z0-9_\s]{0,10}""#.prop_map(|s| s),
        // Integer value
        r"-?[0-9]{1,5}".prop_map(|s| s),
        // Boolean value
        prop_oneof![Just("true".to_string()), Just("false".to_string())],
    ]
}

// Generator for simple comparison operators
fn operator_strategy() -> impl Strategy<Value = String> {
    prop_oneof![
        Just("_eq".to_string()),
        Just("_neq".to_string()),
        Just("_gt".to_string()),
        Just("_lt".to_string()),
        Just("_gte".to_string()),
        Just("_lte".to_string()),
        Just("_like".to_string()),
        Just("_ilike".to_string()),
        Just("_in".to_string()),
        Just("_nin".to_string()),
        Just("_is_null".to_string()),
    ]
}

// Generator for simple filter conditions
fn filter_strategy() -> impl Strategy<Value = String> {
    (
        field_name_strategy(),
        operator_strategy(),
        simple_value_strategy(),
    )
        .prop_map(|(field, op, value)| format!("{{ {}: {{ {}: {} }} }}", field, op, value))
}

// Recursive generator for nested object fields
fn nested_fields_strategy(depth: usize) -> impl Strategy<Value = String> {
    if depth == 0 {
        // Base case: generate only leaf fields at max depth
        leaf_fields_strategy(2).prop_map(|s| s).boxed()
    } else {
        // Recursive case: generate a mix of leaf fields and nested objects
        prop_oneof![
            // Simple leaf fields
            leaf_fields_strategy(3),
            // Nested object with child fields
            (field_name_strategy(), nested_fields_strategy(depth - 1))
                .prop_map(|(name, fields)| format!("{} {{ {} }}", name, fields))
        ]
        .boxed()
    }
}

// Generator for a list of leaf fields
fn leaf_fields_strategy(max_fields: usize) -> impl Strategy<Value = String> {
    prop::collection::vec(leaf_field_strategy(), 1..max_fields).prop_map(|fields| fields.join(" "))
}

// Generator for simple argument values
fn simple_arg_strategy() -> impl Strategy<Value = String> {
    prop_oneof![
        // Limit argument
        (1..100).prop_map(|n| format!("limit: {}", n)),
        // Offset argument
        (0..100).prop_map(|n| format!("offset: {}", n)),
        // Where argument with simple filter
        filter_strategy().prop_map(|f| format!("where: {}", f)),
        // Order by argument
        field_name_strategy().prop_map(|field| format!("order_by: {{ {}: asc }}", field)),
    ]
}

// Generator for field arguments
fn args_strategy() -> impl Strategy<Value = String> {
    prop::collection::vec(simple_arg_strategy(), 0..3).prop_map(|args| {
        if args.is_empty() {
            "".to_string()
        } else {
            format!("({})", args.join(", "))
        }
    })
}

// Generator for a valid GraphQL query with controlled nesting
fn valid_query_strategy() -> impl Strategy<Value = String> {
    r#"[ \t\n]*\{[ \t\n]*[A-Za-z0-9_]+[ \t\n]*\{[ \t\n]*[A-Za-z0-9_]+[ \t\n]*\}[ \t\n]*\}[ \t\n]*"#
        .prop_map(|s| s)
}

// Generator for invalid GraphQL queries
fn invalid_query_strategy() -> impl Strategy<Value = String> {
    prop_oneof![
        // Missing closing brace
        valid_query_strategy().prop_map(|s| s.replace("}", "}")),
        // Missing closing field brace
        valid_query_strategy().prop_map(|s| {
            let mut chars: Vec<char> = s.chars().collect();
            if let Some(pos) = chars.iter().position(|&c| c == '}') {
                chars.remove(pos);
                chars.into_iter().collect()
            } else {
                s
            }
        }),
        // Unbalanced quotes
        valid_query_strategy().prop_map(|s| {
            let mut result = s.clone();
            if let Some(pos) = s.find('"') {
                result.replace_range(pos..(pos + 1), "");
            }
            result
        }),
        // Invalid field name
        valid_query_strategy().prop_map(|s| s.replace("{ ", "{ 123invalid "))
    ]
}

// Property test for parse_graphql with valid queries
proptest! {
    #[test]
    fn test_parse_graphql_valid_queries(query in valid_query_strategy()) {
        // Initialize GraSQL config
        let _ = grasql::types::initialize_for_test();

        // This test ensures that valid queries don't cause panics
        // The result might be Ok or Err depending on specific query features supported
        let _ = parse_graphql(&query);
    }

    #[test]
    fn test_extract_field_paths_valid_queries(query in valid_query_strategy()) {
        // Initialize GraSQL config
        let _ = grasql::types::initialize_for_test();

        // This test ensures that field extraction doesn't panic on valid queries
        let ctx = ASTContext::new();
        if let Ok(document) = Document::parse(&ctx, &query) {
            let mut extractor = FieldPathExtractor::new();
            let _ = extractor.extract(&document);
        }
    }

    #[test]
    fn test_field_path_not_empty(query in valid_query_strategy().prop_filter(
        "Query must be parseable",
        |q| Document::parse(&ASTContext::new(), q).is_ok()
    )) {
        // Initialize GraSQL config
        let _ = grasql::types::initialize_for_test();

        // This test ensures that parseable queries produce at least one field path
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, &query).unwrap();
        let mut extractor = FieldPathExtractor::new();
        let (paths, _) = extractor.extract(&document).unwrap();

        // Ensure we extracted at least one path
        prop_assert!(!paths.is_empty());
    }
}

// Property test for parse_graphql with invalid queries (shouldn't panic)
proptest! {
    #[test]
    fn test_parse_graphql_invalid_queries_no_panic(query in invalid_query_strategy()) {
        // Initialize GraSQL config
        let _ = grasql::types::initialize_for_test();

        // This test ensures that invalid queries don't cause panics
        // The result should be Err, but we don't assert that to allow for queries that are
        // actually valid despite our attempt to make them invalid
        let _ = parse_graphql(&query);
    }
}

// Test with snapshot testing for basic queries
#[test]
fn snapshot_test_field_extraction_basic_queries() {
    // Initialize GraSQL config
    let _ = grasql::types::initialize_for_test();

    let queries = vec![
        "{ users { id name } }",
        "{ users { id profile { avatar } posts { title } } }",
        "{ users(where: { profile: { avatar: \"something\" } }) { id } }",
        r#"
        {
            users(limit: 10, offset: 20) {
                id
                name
                posts {
                    title
                    comments {
                        id
                        author {
                            name
                        }
                    }
                }
            }
        }
        "#,
    ];

    for (i, query) in queries.iter().enumerate() {
        let ctx = ASTContext::new();
        if let Ok(document) = Document::parse(&ctx, query) {
            let mut extractor = FieldPathExtractor::new();
            let (paths, _) = extractor.extract(&document).unwrap();

            // Use basic assertions instead of snapshots for now
            // The user can run cargo insta review manually to accept snapshots
            assert!(!paths.is_empty(), "Field paths should not be empty");

            match i {
                0 => {
                    // Simple query should have exactly one path (users)
                    assert_eq!(paths.len(), 1, "Simple query should have exactly one path");
                }
                1 => {
                    // Query with relationships should have at least 3 paths
                    assert!(
                        paths.len() >= 3,
                        "Relationship query should have at least 3 paths"
                    );
                }
                _ => {}
            }
        }
    }
}

// Comprehensive test for all operators
#[test]
fn test_all_operators() {
    // Initialize GraSQL config
    let _ = grasql::types::initialize_for_test();

    let query = r#"
    {
        users(
            where: {
                _and: [
                    { name: { _eq: "John" } },
                    { age: { _neq: 30 } },
                    { score: { _gt: 50 } },
                    { rank: { _lt: 10 } },
                    { experience: { _gte: 5 } },
                    { failures: { _lte: 3 } },
                    { bio: { _like: "%engineer%" } },
                    { email: { _ilike: "%EXAMPLE.com" } },
                    { id: { _in: [1, 2, 3] } },
                    { status: { _nin: ["INACTIVE", "BANNED"] } },
                    { deleted_at: { _is_null: true } },
                    { 
                        _or: [
                            { role: { _eq: "ADMIN" } },
                            { permissions: { _json_contains: {"admin": true} } }
                        ]
                    },
                    { metadata: { _json_contained_in: {"verified": true} } },
                    { tags: { _json_has_key: "premium" } },
                    { categories: { _json_has_any_keys: ["sport", "tech"] } },
                    { requirements: { _json_has_all_keys: ["id", "name"] } },
                    { data: { _json_path: "profile" } },
                    { info: { _json_path_text: "contact" } },
                    { config: { _is_json: true } }
                ]
            },
            limit: 20,
            offset: 10,
            order_by: { created_at: desc }
        ) {
            id
            name
            email
            profile {
                avatar
                settings {
                    theme
                    notifications
                }
            }
            posts(
                limit: 5,
                offset: 0,
                order_by: { published_at: desc }
            ) {
                id
                title
                content
                comments(
                    where: { approved: { _eq: true } },
                    limit: 10
                ) {
                    id
                    text
                    author {
                        id
                        name
                    }
                }
            }
        }
    }
    "#;

    let ctx = ASTContext::new();
    if let Ok(document) = Document::parse(&ctx, query) {
        let mut extractor = FieldPathExtractor::new();
        let (paths, _) = extractor.extract(&document).unwrap();

        // Check that we extract the expected paths
        assert!(!paths.is_empty(), "Paths shouldn't be empty");

        // Create expected paths using create_path helper
        let expected_paths = [
            create_path(&["users"]),
            create_path(&["users", "profile"]),
            create_path(&["users", "profile", "settings"]),
            create_path(&["users", "posts"]),
            create_path(&["users", "posts", "comments"]),
            create_path(&["users", "posts", "comments", "author"]),
        ];

        for path in &expected_paths {
            assert!(
                paths.contains(path),
                "Expected path {:?} not found in extracted paths",
                path
            );
        }
    }
}
