#![cfg(feature = "test-utils")]

use std::sync::{Arc, Barrier};
use std::thread;

use graphql_query::ast::OperationKind;

#[cfg(test)]
use grasql::insert_raw_for_test;
use grasql::parser::parse_graphql;
use grasql::types::{CachedQueryInfo, GraphQLOperationKind};
use grasql::{add_to_cache, generate_query_id, get_from_cache};

/// Test basic cache functionality
#[test]
fn test_basic_cache_functionality() {
    // Parse a simple query
    let query = "{ users { id name } }";
    let (parsed_info, _) = parse_graphql(query).unwrap();

    // Generate query ID and add to cache
    let query_id = generate_query_id(query);
    add_to_cache(&query_id, parsed_info.clone());

    // Retrieve from cache
    let cached_info = get_from_cache(&query_id).unwrap();

    // Verify document access works
    let document = cached_info.document().unwrap();

    // Check that document contains expected data
    let operation = document.operation(None).unwrap();
    assert_eq!(operation.operation, OperationKind::Query);

    // Check operation kind matches
    assert!(matches!(
        cached_info.operation_kind,
        GraphQLOperationKind::Query
    ));

    // Verify field selection exists
    assert!(!operation.selection_set.is_empty());
}

/// Test concurrent cache access
#[test]
fn test_concurrent_cache_access() {
    // Parse a query to cache
    let query = "{ users { id email posts { title } } }";
    let (parsed_info, _) = parse_graphql(query).unwrap();

    // Add to cache
    let query_id = generate_query_id(query);
    add_to_cache(&query_id, parsed_info);

    // Number of concurrent threads
    let thread_count = 8;
    let barrier = Arc::new(Barrier::new(thread_count));

    // Spawn multiple threads to access the cache concurrently
    let handles: Vec<_> = (0..thread_count)
        .map(|_| {
            let query_id_clone = query_id.clone();
            let barrier_clone = Arc::clone(&barrier);

            thread::spawn(move || {
                // Synchronize all threads to start at the same time
                barrier_clone.wait();

                // Access cached query
                let cached_info = get_from_cache(&query_id_clone).unwrap();

                // Access document and perform some operations
                let document = cached_info.document().unwrap();
                let operation = document.operation(None).unwrap();

                // Verify document data
                assert_eq!(operation.operation, OperationKind::Query);

                // Return some data to verify thread completed successfully
                operation.selection_set.selections.len()
            })
        })
        .collect();

    // Wait for all threads and collect results
    let results: Vec<_> = handles.into_iter().map(|h| h.join().unwrap()).collect();

    // Verify all threads saw the same data
    let first = results[0];
    for &result in &results[1..] {
        assert_eq!(first, result);
    }
}

/// Test fallback reparse behavior when document_ptr is not available
#[test]
fn test_fallback_reparse_behavior() {
    // Parse a query but manually create a version without document_ptr
    let query = "{ users { id name } }";
    let (parsed_info, _) = parse_graphql(query).unwrap();

    // Create a modified copy with no document_ptr
    let modified_info = CachedQueryInfo {
        operation_kind: parsed_info.operation_kind.clone(),
        operation_name: parsed_info.operation_name.clone(),
        field_paths: parsed_info.field_paths.clone(),
        path_index: parsed_info.path_index.clone(),
        column_usage: parsed_info.column_usage.clone(),
        ast_context: parsed_info.ast_context.clone(),
        original_query: parsed_info.original_query.clone(),
        document_ptr: None, // Intentionally set to None to test fallback
    };

    // Add to cache using our test helper
    let query_id = generate_query_id(query);
    insert_raw_for_test(&query_id, modified_info);

    // Retrieve and verify document access works through re-parsing
    let cached_info = get_from_cache(&query_id).unwrap();
    let document = cached_info.document().unwrap();

    // Verify document content is correct despite missing pointer
    let operation = document.operation(None).unwrap();
    assert_eq!(operation.operation, OperationKind::Query);
}

/// Test cache eviction memory safety by filling cache beyond capacity
#[test]
fn test_cache_eviction_memory_safety() {
    // This test verifies that memory is properly managed when cache entries are evicted

    // First fill the cache with many queries to trigger eviction
    let base_query = "{ users(limit: _LIMIT_) { id name } }";
    let num_queries = 2000; // Ensure this is larger than cache size

    // Generate and cache many queries
    for i in 0..num_queries {
        let query = base_query.replace("_LIMIT_", &i.to_string());
        let (parsed_info, _) = parse_graphql(&query).unwrap();
        let query_id = generate_query_id(&query);
        add_to_cache(&query_id, parsed_info);
    }

    // Force garbage collection to ensure any memory issues surface
    let early_query = base_query.replace("_LIMIT_", "0");
    let early_query_id = generate_query_id(&early_query);

    // This should either return None (if evicted) or a valid CachedQueryInfo
    // It should not crash or cause undefined behavior
    match get_from_cache(&early_query_id) {
        Some(cached_info) => {
            // If still in cache, document access should work safely
            if let Some(doc) = cached_info.document() {
                let _ = doc.operation(None);
            }
        }
        None => {
            // Query was evicted, which is expected
        }
    }

    // Try accessing a more recent query
    let recent_query = base_query.replace("_LIMIT_", &(num_queries - 1).to_string());
    let recent_query_id = generate_query_id(&recent_query);

    if let Some(cached_info) = get_from_cache(&recent_query_id) {
        let document = cached_info.document();
        assert!(
            document.is_some(),
            "Document should be accessible for recent cache entry"
        );
    }
}

/// Test that CachedQueryInfo properly handles cloning and dropping
#[test]
fn test_ast_context_droppability() {
    // This test verifies that CachedQueryInfo properly manages its resources
    // when dropped, even when multiple copies exist

    // Parse a query
    let query = "{ users { id name } }";
    let (parsed_info, _) = parse_graphql(query).unwrap();

    // Create a scope to test resource cleanup
    {
        // Clone the AST context to have multiple references
        let context = parsed_info.ast_context.clone().unwrap();

        // Create multiple CachedQueryInfo instances sharing the same context
        let cached1 = CachedQueryInfo::from(parsed_info.clone());
        let cached2 = cached1.clone();

        // Verify document access works for both
        assert!(cached1.document().is_some());
        assert!(cached2.document().is_some());

        // Drop one of the cached instances
        drop(cached1);

        // Verify the remaining instance still works
        let document = cached2.document();
        assert!(
            document.is_some(),
            "Document should still be accessible after dropping a clone"
        );

        // Make sure context is still accessible before end of scope
        assert!(
            Arc::strong_count(&context) >= 1,
            "Context should have strong references"
        );
    }

    // After scope ends, all resources should be properly cleaned up
    // No explicit test needed - it would crash if memory issues exist
}

/// Test cache behavior in a high-concurrency scenario with multiple operations
#[test]
fn test_high_concurrency_mixed_operations() {
    // Create different query types
    let queries = vec![
        "{ users { id name } }",
        "{ posts { id title } }",
        "{ comments { id content } }",
        "mutation { createUser(name: \"test\") { id } }",
    ];

    // Parse and cache all queries
    let ids: Vec<_> = queries
        .iter()
        .map(|q| {
            let (parsed_info, _) = parse_graphql(q).unwrap();
            let query_id = generate_query_id(q);
            add_to_cache(&query_id, parsed_info);
            query_id
        })
        .collect();

    // Number of concurrent threads per query
    let threads_per_query = 5;
    let total_threads = ids.len() * threads_per_query;
    let barrier = Arc::new(Barrier::new(total_threads));

    // Create threads for each query
    let handles: Vec<_> = ids
        .iter()
        .flat_map(|id| {
            let id_clone = id.clone();
            let barrier_clone = Arc::clone(&barrier);

            (0..threads_per_query)
                .map(move |_| {
                    let id_clone = id_clone.clone();
                    let barrier_clone = Arc::clone(&barrier_clone);

                    thread::spawn(move || {
                        // Wait for all threads to be ready
                        barrier_clone.wait();

                        // Perform 50 cache accesses - no sleep between iterations for true concurrency
                        for _ in 0..50 {
                            let cached_info = get_from_cache(&id_clone).unwrap();
                            let document = cached_info.document().unwrap();
                            let _ = document.operation(None).unwrap();
                        }

                        true
                    })
                })
                .collect::<Vec<_>>()
        })
        .collect();

    // Wait for all threads to complete
    for handle in handles {
        assert!(
            handle.join().unwrap(),
            "Thread should complete successfully"
        );
    }
}

/// Test reference counting behavior specifically
#[test]
fn test_arc_reference_counting() {
    // Setup - parse query and create cached info
    let query = "{ users { id } }";
    let (parsed_info, _) = parse_graphql(query).unwrap();

    // Get initial reference count
    let context = parsed_info.ast_context.as_ref().unwrap();
    let initial_count = Arc::strong_count(context);

    // Create cached copies to increase ref count
    let cached1 = CachedQueryInfo::from(parsed_info.clone());
    let cached2 = cached1.clone();

    // Verify ref count increased properly
    assert_eq!(
        Arc::strong_count(context),
        initial_count + 2,
        "Reference count should increase with each clone"
    );

    // Drop one copy
    drop(cached1);

    // Verify ref count decreased but document is still accessible
    assert_eq!(
        Arc::strong_count(context),
        initial_count + 1,
        "Reference count should decrease after drop"
    );

    // Verify document is still accessible from remaining instance
    assert!(cached2.document().is_some());
}

/// Test high concurrency without artificial delays
#[test]
fn test_high_concurrency_without_sleeps() {
    // Parse and cache multiple queries
    let queries = vec!["{ users { id name } }", "{ posts { id title } }"];

    let ids: Vec<_> = queries
        .iter()
        .map(|q| {
            let (parsed_info, _) = parse_graphql(q).unwrap();
            let query_id = generate_query_id(q);
            add_to_cache(&query_id, parsed_info);
            query_id
        })
        .collect();

    // Create multiple threads accessing the cache concurrently
    let threads_per_query = 20; // More threads for higher concurrency
    let total_threads = ids.len() * threads_per_query;
    let barrier = Arc::new(Barrier::new(total_threads));

    // Spawn threads that access the cache concurrently without artificial delays
    let handles: Vec<_> = ids
        .iter()
        .flat_map(|id| {
            let id_clone = id.clone();
            let barrier_clone = Arc::clone(&barrier);

            (0..threads_per_query)
                .map(move |_| {
                    let id_clone = id_clone.clone();
                    let barrier_clone = Arc::clone(&barrier_clone);

                    thread::spawn(move || {
                        // Synchronize all threads to start at the same time
                        barrier_clone.wait();

                        // Access cached query repeatedly in a tight loop - no sleeps
                        for _ in 0..100 {
                            // Higher iteration count for stress testing
                            let cached_info = get_from_cache(&id_clone).unwrap();
                            let document = cached_info.document().unwrap();
                            let _ = document.operation(None).unwrap();
                        }

                        true
                    })
                })
                .collect::<Vec<_>>()
        })
        .collect();

    // Wait for all threads to complete
    for handle in handles {
        assert!(
            handle.join().unwrap(),
            "Thread should complete successfully without artificial delays"
        );
    }
}

/// Test document validity across thread boundaries
#[test]
fn test_document_validity_across_threads() {
    // Parse and cache a query
    let query = "{ users { id posts { title comments { content } } } }";
    let (parsed_info, _) = parse_graphql(query).unwrap();
    let query_id = generate_query_id(query);
    add_to_cache(&query_id, parsed_info);

    // Spawn a thread that accesses the cached document
    let thread_handle = thread::spawn(move || {
        // Get from cache in the new thread
        let cached_info = get_from_cache(&query_id).unwrap();

        // Access document across thread boundary
        let document = cached_info.document().unwrap();

        // Perform deep inspection of the document to verify it's fully valid
        let operation = document.operation(None).unwrap();

        // Check first-level selections
        let users_selection = &operation.selection_set.selections[0];
        let users_field = users_selection.field().unwrap();
        assert_eq!(users_field.name, "users");

        // Check nested selections - first is id field
        let id_selection = &users_field.selection_set.selections[0];
        let id_field = id_selection.field().unwrap();
        assert_eq!(id_field.name, "id");

        // Check nested selections - second is posts field
        let posts_selection = &users_field.selection_set.selections[1];
        let posts_field = posts_selection.field().unwrap();
        assert_eq!(posts_field.name, "posts");

        // Check deeply nested selections
        let title_selection = &posts_field.selection_set.selections[0];
        let title_field = title_selection.field().unwrap();
        assert_eq!(title_field.name, "title");

        // Very deeply nested
        let comments_selection = &posts_field.selection_set.selections[1];
        let comments_field = comments_selection.field().unwrap();
        let content_selection = &comments_field.selection_set.selections[0];
        let content_field = content_selection.field().unwrap();

        assert_eq!(comments_field.name, "comments");
        assert_eq!(content_field.name, "content");

        true
    });

    assert!(
        thread_handle.join().unwrap(),
        "Document should be valid across thread boundaries"
    );
}
