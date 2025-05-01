/// GraSQL - GraphQL to SQL translation library
///
/// GraSQL is a high-performance library for translating GraphQL queries to SQL.
/// It provides a bridge between GraphQL and relational databases, allowing
/// GraphQL queries to be efficiently executed against SQL databases.
///
/// The library is written in Rust and exposes its functionality to Elixir
/// through NIFs (Native Implemented Functions).
// Module declarations
mod atoms;
mod cache;
mod config;
mod nif;
mod parser;
mod sql;
mod types;

// Re-exports for public API
pub use config::Config;
pub use types::{GraphQLOperationKind, ParsedQueryInfo};

// Module initialization
fn load(_env: rustler::Env, _info: rustler::Term) -> bool {
    true
}

// Register NIF functions
rustler::init!("Elixir.GraSQL.Native", load = load);
