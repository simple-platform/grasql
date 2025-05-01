use criterion::{black_box, criterion_group, criterion_main, Criterion};
use graphql_query::ast::{ASTContext, Document, ParseNode};

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
query GetUserWithData($userId: ID!, $includeDetails: Boolean!) {
  user(id: $userId) {
    id
    name
    email
    profile @include(if: $includeDetails) {
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
}

fragment UserBasic on User {
  id
  name
  email
}";

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

    group.finish();
}

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

    group.finish();
}

criterion_group!(benches, bench_direct_ast_parse, bench_query_hashing);
criterion_main!(benches);
