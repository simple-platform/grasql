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
fn load(_env: rustler::Env, opts: rustler::Term) -> bool {
    let result: Result<Config, rustler::Error> = rustler::Decoder::decode(opts);
    match result {
        Ok(config) => {
            // Store the configuration in the global state
            match config::CONFIG.lock() {
                Ok(mut cfg) => {
                    *cfg = Some(config.clone());
                    true // Initialization successful
                }
                Err(_) => {
                    eprintln!("Failed to acquire config lock during initialization");
                    false // Failed to lock CONFIG
                }
            }
        }
        Err(err) => {
            eprintln!(
                "Failed to decode configuration during initialization: {:?}",
                err
            );
            false // Failed to decode configuration
        }
    }
}

// Register NIF functions
rustler::init!("Elixir.GraSQL.Native", load = load);
