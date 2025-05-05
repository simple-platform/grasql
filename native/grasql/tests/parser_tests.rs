use graphql_query::ast::{ASTContext, Document, ParseNode};
use grasql::extraction::FieldPathExtractor;
use grasql::interning::intern_str;
use grasql::parser::parse_graphql;
use grasql::types::FieldPath;
use std::collections::HashSet;

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
    let query = r#"
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

    let paths = extract_field_paths(query);

    // Test for expected paths
    assert_path_exists(&paths, &["insert_users"]);
    assert_path_exists(&paths, &["insert_users", "returning"]);
    assert_path_exists(&paths, &["insert_users", "returning", "profile"]);
    assert_path_exists(&paths, &["update_posts"]);
    assert_path_exists(&paths, &["update_posts", "returning"]);
}

#[test]
fn test_variables() {
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
    assert!(request.field_names.contains(&"users".to_string()));
    assert!(request.field_names.contains(&"posts".to_string()));
}

#[test]
fn test_invalid_queries() {
    // Test syntax error
    let invalid_query = "{ users { invalid syntax }";
    let result = parse_graphql(invalid_query);
    assert!(result.is_err());

    // Test empty document
    let empty_query = "";
    let result = parse_graphql(empty_query);
    assert!(result.is_err());
}
