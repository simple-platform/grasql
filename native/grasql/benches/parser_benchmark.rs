use criterion::{black_box, criterion_group, criterion_main, BenchmarkId, Criterion};
use graphql_query::ast::{ASTContext, Document, ParseNode};
use grasql::extraction::FieldPathExtractor;
use grasql::parser::parse_graphql;

// Sample queries for benchmarking
const SIMPLE_QUERY: &str = "{ users { id name } }";

const MEDIUM_QUERY: &str = "
query GetUser($id: ID!) {
  user(id: $id) {
    id
    name
    email
    posts(first: 5, orderBy: { createdAt: DESC }) {
      id
      title
      body
      tags { id name }
    }
  }
}";

const COMPLEX_QUERY: &str = "
query GetUserWithData($userId: ID!) {
  user(id: $userId) {
    id
    name
    email
    profile {
      avatar
      bio
      location
      website
    }
    posts(
      first: 10
      orderBy: { createdAt: DESC }
      where: { published: { _eq: true } }
    ) {
      id
      title
      body
      createdAt
      updatedAt
      tags {
        id
        name
      }
      comments(first: 5) {
        id
        body
        author {
          id
          name
        }
      }
    }
    followers(first: 10) {
      id
      name
    }
    following(first: 10) {
      id
      name
    }
  }
}";

// Add new specialized query samples for benchmarking

// Deeply nested query (5+ levels of nesting)
const DEEPLY_NESTED_QUERY: &str = "
{
  organizations {
    id
    name
    departments {
      id
      name
      teams {
        id
        name
        projects {
          id
          name
          tasks {
            id
            name
            subtasks {
              id
              name
              assignee {
                id
                name
                skills {
                  id
                  name
                  level
                }
              }
            }
          }
        }
      }
    }
  }
}";

// Query with complex filters
const COMPLEX_FILTERS_QUERY: &str = "
{
  users(where: {
    _and: [
      { name: { _like: \"%John%\" } },
      { email: { _ilike: \"%example.com\" } },
      { 
        _or: [
          { age: { _gt: 18 } },
          { status: { _eq: \"ACTIVE\" } }
        ]
      },
      {
        profile: {
          _and: [
            { verified: { _eq: true } },
            { 
              location: { 
                city: { _eq: \"New York\" }
              }
            }
          ]
        }
      }
    ]
  }) {
    id
    name
    email
  }
}";

// Query with aggregations
const AGGREGATION_QUERY: &str = "
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
  posts_aggregate(where: { author: { name: { _eq: \"John\" } } }) {
    aggregate {
      count
    }
  }
}";

// Query with pagination and sorting
const PAGINATION_SORTING_QUERY: &str = "
{
  users(
    limit: 10, 
    offset: 20, 
    order_by: { name: asc, created_at: desc }
  ) {
    id
    name
    email
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
    content
  }
}";

// Query combining multiple features
const COMBINED_FEATURES_QUERY: &str = "
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
}";

// Mutation query
const MUTATION_QUERY: &str = "
mutation {
  insert_users(
    objects: [
      { name: \"John\", email: \"john@example.com\" },
      { name: \"Jane\", email: \"jane@example.com\" }
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
}";

// Benchmark for direct AST parsing (original benchmark)
fn bench_direct_ast_parse(c: &mut Criterion) {
    let mut group = c.benchmark_group("direct_ast_parse");

    group.bench_function("simple_query", |b| {
        b.iter(|| {
            let ctx = ASTContext::new();
            let _ = Document::parse(&ctx, black_box(SIMPLE_QUERY)).unwrap();
        });
    });

    group.bench_function("medium_query", |b| {
        b.iter(|| {
            let ctx = ASTContext::new();
            let _ = Document::parse(&ctx, black_box(MEDIUM_QUERY)).unwrap();
        });
    });

    group.bench_function("complex_query", |b| {
        b.iter(|| {
            let ctx = ASTContext::new();
            let _ = Document::parse(&ctx, black_box(COMPLEX_QUERY)).unwrap();
        });
    });

    // Add new query types to the benchmark
    group.bench_function("deeply_nested_query", |b| {
        b.iter(|| {
            let ctx = ASTContext::new();
            let _ = Document::parse(&ctx, black_box(DEEPLY_NESTED_QUERY)).unwrap();
        });
    });

    group.bench_function("complex_filters_query", |b| {
        b.iter(|| {
            let ctx = ASTContext::new();
            let _ = Document::parse(&ctx, black_box(COMPLEX_FILTERS_QUERY)).unwrap();
        });
    });

    group.bench_function("aggregation_query", |b| {
        b.iter(|| {
            let ctx = ASTContext::new();
            let _ = Document::parse(&ctx, black_box(AGGREGATION_QUERY)).unwrap();
        });
    });

    group.bench_function("pagination_sorting_query", |b| {
        b.iter(|| {
            let ctx = ASTContext::new();
            let _ = Document::parse(&ctx, black_box(PAGINATION_SORTING_QUERY)).unwrap();
        });
    });

    group.bench_function("combined_features_query", |b| {
        b.iter(|| {
            let ctx = ASTContext::new();
            let _ = Document::parse(&ctx, black_box(COMBINED_FEATURES_QUERY)).unwrap();
        });
    });

    group.bench_function("mutation_query", |b| {
        b.iter(|| {
            let ctx = ASTContext::new();
            let _ = Document::parse(&ctx, black_box(MUTATION_QUERY)).unwrap();
        });
    });

    group.finish();
}

// Original query hashing benchmark
fn bench_query_hashing(c: &mut Criterion) {
    use xxhash_rust::xxh3::xxh3_64;

    let mut group = c.benchmark_group("query_hashing");

    group.bench_function("simple_query", |b| {
        b.iter(|| {
            let hash = xxh3_64(black_box(SIMPLE_QUERY.as_bytes()));
            let _ = format!("q_{:x}", hash);
        });
    });

    group.bench_function("medium_query", |b| {
        b.iter(|| {
            let hash = xxh3_64(black_box(MEDIUM_QUERY.as_bytes()));
            let _ = format!("q_{:x}", hash);
        });
    });

    group.bench_function("complex_query", |b| {
        b.iter(|| {
            let hash = xxh3_64(black_box(COMPLEX_QUERY.as_bytes()));
            let _ = format!("q_{:x}", hash);
        });
    });

    // Add new query types to hashing benchmark
    group.bench_function("deeply_nested_query", |b| {
        b.iter(|| {
            let hash = xxh3_64(black_box(DEEPLY_NESTED_QUERY.as_bytes()));
            let _ = format!("q_{:x}", hash);
        });
    });

    group.bench_function("complex_filters_query", |b| {
        b.iter(|| {
            let hash = xxh3_64(black_box(COMPLEX_FILTERS_QUERY.as_bytes()));
            let _ = format!("q_{:x}", hash);
        });
    });

    group.finish();
}

// New benchmark for field path extraction
fn bench_field_extraction(c: &mut Criterion) {
    let mut group = c.benchmark_group("field_path_extraction");

    // Define a helper function for benchmarking extraction
    let _bench_extraction = |b: &mut criterion::Bencher, query: &str, _name: &str| {
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).unwrap();

        b.iter(|| {
            let mut extractor = FieldPathExtractor::new();
            let _ = extractor.extract(black_box(&document)).unwrap();
        });
    };

    // Benchmark all query types
    let queries = [
        ("simple_query", SIMPLE_QUERY),
        ("medium_query", MEDIUM_QUERY),
        ("complex_query", COMPLEX_QUERY),
        ("deeply_nested_query", DEEPLY_NESTED_QUERY),
        ("complex_filters_query", COMPLEX_FILTERS_QUERY),
        ("aggregation_query", AGGREGATION_QUERY),
        ("pagination_sorting_query", PAGINATION_SORTING_QUERY),
        ("combined_features_query", COMBINED_FEATURES_QUERY),
        ("mutation_query", MUTATION_QUERY),
    ];

    for (name, query) in queries.iter() {
        group.bench_with_input(BenchmarkId::new("extract", name), query, |b, q| {
            let ctx = ASTContext::new();
            let document = Document::parse(&ctx, q).unwrap();

            b.iter(|| {
                let mut extractor = FieldPathExtractor::new();
                let _ = extractor.extract(black_box(&document)).unwrap();
            });
        });
    }

    group.finish();
}

// New benchmark for the full parse_graphql function
fn bench_parse_graphql(c: &mut Criterion) {
    let mut group = c.benchmark_group("parse_graphql");

    // Benchmark all query types
    let queries = [
        ("simple_query", SIMPLE_QUERY),
        ("medium_query", MEDIUM_QUERY),
        ("complex_query", COMPLEX_QUERY),
        ("deeply_nested_query", DEEPLY_NESTED_QUERY),
        ("complex_filters_query", COMPLEX_FILTERS_QUERY),
        ("aggregation_query", AGGREGATION_QUERY),
        ("pagination_sorting_query", PAGINATION_SORTING_QUERY),
        ("combined_features_query", COMBINED_FEATURES_QUERY),
        ("mutation_query", MUTATION_QUERY),
    ];

    for (name, query) in queries.iter() {
        group.bench_with_input(BenchmarkId::new("parse", name), query, |b, q| {
            b.iter(|| {
                let _ = parse_graphql(black_box(q)).unwrap();
            });
        });
    }

    group.finish();
}

criterion_group!(
    benches,
    bench_direct_ast_parse,
    bench_query_hashing,
    bench_field_extraction,
    bench_parse_graphql
);
criterion_main!(benches);
