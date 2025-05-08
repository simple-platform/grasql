//! Tests that validate ResolutionRequest generation for each sample GraphQL query
//! These tests verify that the query parsing phase (Phase 1) correctly
//! extracts the expected structures from sample GraphQL queries.

use grasql::parser::parse_graphql;
use grasql::types::{CachedQueryInfo, GraphQLOperationKind, ResolutionRequest};
use grasql::{add_to_cache, generate_query_id};

/// Helper function to parse a query and add it to the cache
fn parse_and_cache(query: &str) -> Result<(CachedQueryInfo, ResolutionRequest), String> {
    // Parse the query
    let (info, request) = parse_graphql(query)?;

    // Generate query ID
    let query_id = generate_query_id(query);

    // Convert to CachedQueryInfo
    let mut cached_info: CachedQueryInfo = info.clone().into();

    // Add the resolution request to the cached info
    cached_info.resolution_request = Some(request.clone());

    // Add to cache using the public function
    add_to_cache(&query_id, info);

    Ok((cached_info, request))
}

/// Helper function to initialize GraSQL for tests
fn initialize_grasql() {
    grasql::types::initialize_for_test().expect("Failed to initialize GraSQL");
}

/// Helper function to verify basic ResolutionRequest structure
fn verify_basic_structure(
    request: &ResolutionRequest,
    expected_strings: &[&str],
    expected_op_type: u8,
    expected_root_field: &str,
) {
    // Check strings
    for string in expected_strings {
        assert!(
            request.strings.contains(&string.to_string()),
            "Missing expected string: {}",
            string
        );
    }

    // Check basic structure
    assert!(!request.query_id.is_empty(), "query_id should not be empty");
    assert!(!request.paths.is_empty(), "paths should not be empty");
    assert!(!request.path_dir.is_empty(), "path_dir should not be empty");
    assert!(
        !request.path_types.is_empty(),
        "path_types should not be empty"
    );

    // Check operation type
    let op_found = request.ops.iter().any(|(field_idx, op_type)| {
        let field_name = &request.strings[*field_idx as usize];
        *op_type == expected_op_type && field_name == expected_root_field
    });

    assert!(
        op_found,
        "Expected operation type {} for field {} not found",
        expected_op_type, expected_root_field
    );
}

/// Helper function to verify a table path exists
fn verify_table_path(request: &ResolutionRequest, table: &str) {
    let table_idx = request
        .strings
        .iter()
        .position(|s| s == table)
        .expect(&format!("Table '{}' not found in strings", table)) as u32;

    // Find the path_id for this table
    let path_id = find_path_id_for_table(request, table_idx);

    assert!(path_id.is_some(), "No path found for table {}", table);
    let path_id = path_id.unwrap();

    // Verify the path type is table (0)
    assert_eq!(
        request.path_types[path_id], 0,
        "Path for '{}' should be a table (type 0)",
        table
    );

    // Verify columns exist for this table
    let table_cols = request.cols.iter().find(|(idx, _)| *idx == table_idx);

    assert!(table_cols.is_some(), "No columns found for table {}", table);
}

/// Helper function to verify a relationship path exists
fn verify_relationship_path(request: &ResolutionRequest, parent: &str, child: &str) {
    // Get string indices
    let parent_idx = request
        .strings
        .iter()
        .position(|s| s == parent)
        .expect(&format!("Parent '{}' not found in strings", parent)) as u32;

    let child_idx = request
        .strings
        .iter()
        .position(|s| s == child)
        .expect(&format!("Child '{}' not found in strings", child)) as u32;

    // Find parent path_id
    let parent_path_id = find_path_id_for_table(request, parent_idx);
    assert!(
        parent_path_id.is_some(),
        "No path found for parent {}",
        parent
    );

    // Find relationship path_id
    let mut relationship_path_id = None;
    for path_id in 0..request.path_types.len() {
        if request.path_types[path_id] == 1 {
            // 1 = relationship
            // Get path
            let start_offset = request.path_dir[path_id] as usize;
            let end_offset = if path_id + 1 < request.path_dir.len() {
                request.path_dir[path_id + 1] as usize
            } else {
                request.paths.len()
            };

            let path_length = request.paths[start_offset] as usize;
            let path = &request.paths[start_offset + 1..start_offset + 1 + path_length];

            // Check if this path includes parent and child
            if path.contains(&parent_idx) && path.contains(&child_idx) {
                relationship_path_id = Some(path_id);
                break;
            }
        }
    }

    assert!(
        relationship_path_id.is_some(),
        "No relationship path found between {} and {}",
        parent,
        child
    );

    // Verify the path type is relationship (1)
    let rel_path_id = relationship_path_id.unwrap();
    assert_eq!(
        request.path_types[rel_path_id], 1,
        "Path for relationship should be type 1"
    );
}

/// Helper function to find the path_id for a table
fn find_path_id_for_table(request: &ResolutionRequest, table_idx: u32) -> Option<usize> {
    for path_id in 0..request.path_types.len() {
        if request.path_types[path_id] == 0 {
            // 0 = table
            // Get path
            let start_offset = request.path_dir[path_id] as usize;
            let path_length = request.paths[start_offset] as usize;
            let path = &request.paths[start_offset + 1..start_offset + 1 + path_length];

            // Check if this path is for the table
            if path.contains(&table_idx) {
                return Some(path_id);
            }
        }
    }

    None
}

/// Helper function to verify columns are present for a table
fn verify_columns(request: &ResolutionRequest, table: &str, columns: &[&str]) {
    // Get table index
    let table_idx = request
        .strings
        .iter()
        .position(|s| s == table)
        .expect(&format!("Table '{}' not found in strings", table)) as u32;

    // Find columns for this table
    let table_cols = request
        .cols
        .iter()
        .find(|(idx, _)| *idx == table_idx)
        .map(|(_, cols)| cols);

    assert!(table_cols.is_some(), "No columns found for table {}", table);
    let table_cols = table_cols.unwrap();

    // Verify each expected column
    for col in columns {
        let col_idx = request
            .strings
            .iter()
            .position(|s| s == *col)
            .expect(&format!("Column '{}' not found in strings", col)) as u32;

        assert!(
            table_cols.contains(&col_idx),
            "Column '{}' not found for table '{}'",
            col,
            table
        );
    }
}

/// Helper function to verify document pointer is preserved
fn verify_document_preserved(info: &grasql::types::ParsedQueryInfo) {
    assert!(
        info.document_ptr.is_some(),
        "Document pointer should be preserved for caching"
    );

    // Verify we can get a valid document
    assert!(
        info.document().is_some(),
        "Should be able to get document from pointer"
    );
}

/// Helper function to verify query is cached
fn verify_query_cached(query: &str) {
    // Parse and explicitly add to cache
    let _ = parse_and_cache(query);

    // Now verify it's in the cache
    let query_id = generate_query_id(query);
    let cached = grasql::get_from_cache(&query_id);

    assert!(cached.is_some(), "Query should be cached after parsing");
}

//
// Tests for basic queries (Sample 1 and 2)
//
#[test]
fn test_sample_01_simple_query() {
    initialize_grasql();

    let query = r#"{
      users {
        id
        name
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::Query);

    // Verify structure
    verify_basic_structure(
        &request,
        &["users", "id", "name"],
        0, // Query
        "users",
    );

    // Verify table path
    verify_table_path(&request, "users");

    // Verify columns
    verify_columns(&request, "users", &["id", "name"]);

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}

#[test]
fn test_sample_02_query_with_arguments() {
    initialize_grasql();

    let query = r#"{
      user(id: 123) {
        id
        name
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::Query);

    // Verify structure
    verify_basic_structure(
        &request,
        &["user", "id", "name"],
        0, // Query
        "user",
    );

    // Verify table path
    verify_table_path(&request, "user");

    // Verify columns
    verify_columns(&request, "user", &["id", "name"]);

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}

//
// Tests for relationships (Sample 3 and 13)
//
#[test]
fn test_sample_03_basic_relationship() {
    initialize_grasql();

    let query = r#"{
      users {
        id
        posts {
          title
        }
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::Query);

    // Verify structure
    verify_basic_structure(
        &request,
        &["users", "id", "posts", "title"],
        0, // Query
        "users",
    );

    // Verify table and relationship paths
    verify_table_path(&request, "users");
    verify_relationship_path(&request, "users", "posts");

    // Verify columns
    verify_columns(&request, "users", &["id"]);
    verify_columns(&request, "posts", &["title"]);

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}

#[test]
fn test_sample_13_many_to_many_relationship() {
    initialize_grasql();

    let query = r#"{
      users {
        id
        name
        categories {
          name
        }
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::Query);

    // Verify structure
    verify_basic_structure(
        &request,
        &["users", "id", "name", "categories"],
        0, // Query
        "users",
    );

    // Verify table and relationship paths
    verify_table_path(&request, "users");
    verify_relationship_path(&request, "users", "categories");

    // Verify columns
    verify_columns(&request, "users", &["id", "name"]);
    verify_columns(&request, "categories", &["name"]);

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}

//
// Tests for filtering (Samples 4, 5, 12)
//
#[test]
fn test_sample_04_basic_filtering() {
    initialize_grasql();

    let query = r#"{
      users(where: { name: { _eq: "John" } }) {
        id
        name
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::Query);

    // Verify structure
    verify_basic_structure(
        &request,
        &["users", "id", "name"],
        0, // Query
        "users",
    );

    // Verify table path
    verify_table_path(&request, "users");

    // Verify columns
    verify_columns(&request, "users", &["id", "name"]);

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}

#[test]
fn test_sample_05_nested_filtering() {
    initialize_grasql();

    let query = r#"{
      users(where: { posts: { title: { _like: "%test%" } } }) {
        id
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::Query);

    // Verify structure
    verify_basic_structure(
        &request,
        &["users", "id", "posts", "title"],
        0, // Query
        "users",
    );

    // Verify table and relationship paths
    verify_table_path(&request, "users");
    verify_relationship_path(&request, "users", "posts");

    // Verify columns
    verify_columns(&request, "users", &["id"]);
    verify_columns(&request, "posts", &["title"]);

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}

#[test]
fn test_sample_12_complex_boolean_logic() {
    initialize_grasql();

    let query = r#"{
      users(
        where: {
          _or: [
            { name: { _like: "%John%" } }
            { _and: [{ age: { _gt: 30 } }, { active: { _eq: true } }] }
          ]
        }
      ) {
        id
        name
        age
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::Query);

    // Verify structure
    verify_basic_structure(
        &request,
        &["users", "id", "name", "age", "active"],
        0, // Query
        "users",
    );

    // Verify table path
    verify_table_path(&request, "users");

    // Verify columns
    verify_columns(&request, "users", &["id", "name", "age"]);

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}

//
// Tests for pagination and sorting (Samples 6, 7)
//
#[test]
fn test_sample_06_pagination() {
    initialize_grasql();

    let query = r#"{
      users(limit: 10, offset: 20) {
        id
        name
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::Query);

    // Verify structure
    verify_basic_structure(
        &request,
        &["users", "id", "name"],
        0, // Query
        "users",
    );

    // Verify table path
    verify_table_path(&request, "users");

    // Verify columns
    verify_columns(&request, "users", &["id", "name"]);

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}

#[test]
fn test_sample_07_sorting() {
    initialize_grasql();

    let query = r#"{
      users(order_by: { name: asc }) {
        id
        name
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::Query);

    // Verify structure
    verify_basic_structure(
        &request,
        &["users", "id", "name"],
        0, // Query
        "users",
    );

    // Verify table path
    verify_table_path(&request, "users");

    // Verify columns
    verify_columns(&request, "users", &["id", "name"]);

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}

//
// Tests for aggregation (Samples 8, 9, 10)
//
#[test]
fn test_sample_08_basic_aggregation() {
    initialize_grasql();

    let query = r#"{
      users_aggregate {
        aggregate {
          count
        }
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::Query);

    // Verify structure
    verify_basic_structure(
        &request,
        &["users_aggregate", "aggregate", "count"],
        0, // Query
        "users_aggregate",
    );

    // Verify table path
    verify_table_path(&request, "users_aggregate");

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}

#[test]
fn test_sample_09_aggregation_with_nodes() {
    initialize_grasql();

    let query = r#"{
      users_aggregate {
        aggregate {
          count
          max {
            id
          }
        }
        nodes {
          name
        }
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::Query);

    // Verify structure
    verify_basic_structure(
        &request,
        &[
            "users_aggregate",
            "aggregate",
            "count",
            "max",
            "id",
            "nodes",
            "name",
        ],
        0, // Query
        "users_aggregate",
    );

    // Verify table path
    verify_table_path(&request, "users_aggregate");

    // Verify columns
    verify_columns(&request, "users_aggregate", &["name"]);

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}

#[test]
fn test_sample_10_nested_aggregation() {
    initialize_grasql();

    let query = r#"{
      users {
        id
        name
        posts_aggregate {
          aggregate {
            count
          }
        }
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::Query);

    // Verify structure
    verify_basic_structure(
        &request,
        &[
            "users",
            "id",
            "name",
            "posts_aggregate",
            "aggregate",
            "count",
        ],
        0, // Query
        "users",
    );

    // Verify table path
    verify_table_path(&request, "users");
    verify_relationship_path(&request, "users", "posts_aggregate");

    // Verify columns
    verify_columns(&request, "users", &["id", "name"]);

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}

//
// Test for distinct queries (Sample 11)
//
#[test]
fn test_sample_11_distinct_queries() {
    initialize_grasql();

    let query = r#"{
      users(distinct_on: name) {
        id
        name
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::Query);

    // Verify structure
    verify_basic_structure(
        &request,
        &["users", "id", "name"],
        0, // Query
        "users",
    );

    // Verify table path
    verify_table_path(&request, "users");

    // Verify columns
    verify_columns(&request, "users", &["id", "name"]);

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}

//
// Test for complex combined query (Sample 14)
//
#[test]
fn test_sample_14_complex_combined_query() {
    initialize_grasql();

    let query = r#"{
      users(
        where: { age: { _gt: 21 } }
        order_by: { name: asc }
        limit: 5
        offset: 10
      ) {
        id
        name
        posts(
          where: { published: { _eq: true } }
          order_by: { created_at: desc }
          limit: 3
        ) {
          title
          content
        }
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::Query);

    // Verify structure
    verify_basic_structure(
        &request,
        &[
            "users",
            "id",
            "name",
            "posts",
            "title",
            "content",
            "age",
            "published",
        ],
        0, // Query
        "users",
    );

    // Verify table and relationship paths
    verify_table_path(&request, "users");
    verify_relationship_path(&request, "users", "posts");

    // Verify columns
    verify_columns(&request, "users", &["id", "name", "age"]);
    verify_columns(&request, "posts", &["title", "content", "published"]);

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}

//
// Tests for insert mutations (Samples 15, 16)
//
#[test]
fn test_sample_15_insert_mutation() {
    initialize_grasql();

    let query = r#"mutation {
      insert_users_one(
        object: { name: "John Doe", email: "john@example.com", age: 30 }
      ) {
        id
        name
        email
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::InsertMutation);

    // Verify structure
    verify_basic_structure(
        &request,
        &["insert_users_one", "id", "name", "email", "age"],
        1, // InsertMutation
        "insert_users_one",
    );

    // Verify table path
    verify_table_path(&request, "insert_users_one");

    // Verify columns
    verify_columns(&request, "insert_users_one", &["id", "name", "email"]);

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}

#[test]
fn test_sample_16_batch_insert_mutation() {
    initialize_grasql();

    let query = r#"mutation {
      insert_users(
        objects: [
          { name: "John Doe", email: "john@example.com", age: 30 }
          { name: "Jane Smith", email: "jane@example.com", age: 28 }
        ]
      ) {
        affected_rows
        returning {
          id
          name
        }
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::InsertMutation);

    // Verify structure
    verify_basic_structure(
        &request,
        &[
            "insert_users",
            "affected_rows",
            "returning",
            "id",
            "name",
            "email",
            "age",
        ],
        1, // InsertMutation
        "insert_users",
    );

    // Verify table path
    verify_table_path(&request, "insert_users");

    // Verify columns
    verify_columns(&request, "insert_users", &["id", "name"]);

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}

//
// Tests for update mutations (Samples 17, 18)
//
#[test]
fn test_sample_17_update_mutation() {
    initialize_grasql();

    let query = r#"mutation {
      update_users_by_pk(
        pk_columns: { id: 123 }
        _set: { name: "Updated Name", email: "updated@example.com" }
      ) {
        id
        name
        email
        updated_at
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::UpdateMutation);

    // Verify structure
    verify_basic_structure(
        &request,
        &["update_users_by_pk", "id", "name", "email", "updated_at"],
        2, // UpdateMutation
        "update_users_by_pk",
    );

    // Verify table path
    verify_table_path(&request, "update_users_by_pk");

    // Verify columns
    verify_columns(
        &request,
        "update_users_by_pk",
        &["id", "name", "email", "updated_at"],
    );

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}

#[test]
fn test_sample_18_batch_update_mutation() {
    initialize_grasql();

    let query = r#"mutation {
      update_users(
        where: { active: { _eq: false } }
        _set: { active: true, updated_at: "2023-06-15T12:00:00Z" }
      ) {
        affected_rows
        returning {
          id
          name
          active
          updated_at
        }
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::UpdateMutation);

    // Verify structure
    verify_basic_structure(
        &request,
        &[
            "update_users",
            "affected_rows",
            "returning",
            "id",
            "name",
            "active",
            "updated_at",
        ],
        2, // UpdateMutation
        "update_users",
    );

    // Verify table path
    verify_table_path(&request, "update_users");

    // Verify columns
    verify_columns(
        &request,
        "update_users",
        &["id", "name", "active", "updated_at"],
    );

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}

//
// Tests for delete mutations (Samples 19, 20)
//
#[test]
fn test_sample_19_delete_mutation() {
    initialize_grasql();

    let query = r#"mutation {
      delete_users_by_pk(id: 123) {
        id
        name
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::DeleteMutation);

    // Verify structure
    verify_basic_structure(
        &request,
        &["delete_users_by_pk", "id", "name"],
        3, // DeleteMutation
        "delete_users_by_pk",
    );

    // Verify table path
    verify_table_path(&request, "delete_users_by_pk");

    // Verify columns
    verify_columns(&request, "delete_users_by_pk", &["id", "name"]);

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}

#[test]
fn test_sample_20_batch_delete_mutation() {
    initialize_grasql();

    let query = r#"mutation {
      delete_users(
        where: {
          last_login: { _lt: "2022-01-01T00:00:00Z" }
          active: { _eq: false }
        }
      ) {
        affected_rows
        returning {
          id
          name
          email
        }
      }
    }"#;

    let (info, request) = parse_graphql(query).expect("Failed to parse query");

    // Check operation kind
    assert_eq!(info.operation_kind, GraphQLOperationKind::DeleteMutation);

    // Verify structure
    verify_basic_structure(
        &request,
        &[
            "delete_users",
            "affected_rows",
            "returning",
            "id",
            "name",
            "email",
            "last_login",
            "active",
        ],
        3, // DeleteMutation
        "delete_users",
    );

    // Verify table path
    verify_table_path(&request, "delete_users");

    // Verify columns
    verify_columns(&request, "delete_users", &["id", "name", "email"]);

    // Verify document and caching
    verify_document_preserved(&info);
    verify_query_cached(query);
}
