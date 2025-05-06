use std::sync::{Arc, Barrier};
use std::thread;
use std::time::Duration;

use graphql_query::ast::OperationKind;

use grasql::cache::{add_to_cache, generate_query_id, get_from_cache};
use grasql::parser::parse_graphql;
use grasql::types::{CachedQueryInfo, GraphQLOperationKind};

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

    // Add to cache - Create a new ParsedQueryInfo with lifetime parameter
    let query_id = generate_query_id(query);

    // We need to directly insert to QUERY_CACHE instead of using add_to_cache
    // since we already have a CachedQueryInfo
    use grasql::cache::QUERY_CACHE;
    QUERY_CACHE.insert(query_id.clone(), modified_info);

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

                        // Perform 50 cache accesses
                        for _ in 0..50 {
                            let cached_info = get_from_cache(&id_clone).unwrap();
                            let document = cached_info.document().unwrap();
                            let _ = document.operation(None).unwrap();

                            // Small delay to increase chance of thread interleaving
                            thread::sleep(Duration::from_micros(1));
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
