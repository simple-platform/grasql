/// String interning module
///
/// This module provides efficient string interning capabilities using the lasso crate.
/// String interning reduces memory usage by storing each unique string only once,
/// and representing strings as small integer IDs in the rest of the application.
use lasso::{Capacity, Rodeo, Spur};
use once_cell::sync::Lazy;
use std::sync::Mutex;

/// Global string interner
pub static STRING_INTERNER: Lazy<Mutex<Rodeo>> = Lazy::new(|| {
    // Get capacity from configuration
    let capacity_size = match crate::config::CONFIG.lock() {
        Ok(cfg) => match &*cfg {
            Some(c) => c.string_interner_capacity,
            None => 10000,
        },
        Err(_) => 10000, // Default if config lock fails
    };

    // Create a proper Capacity instance for the interner
    let capacity = Capacity::for_strings(capacity_size);

    Mutex::new(Rodeo::with_capacity(capacity))
});

/// Interns a string and returns its symbol ID
#[inline(always)]
pub fn intern_str(s: &str) -> Spur {
    match STRING_INTERNER.lock() {
        Ok(mut interner) => interner.get_or_intern(s),
        Err(poisoned) => {
            eprintln!("WARNING: STRING_INTERNER lock poisoned, using recovered lock");
            poisoned.into_inner().get_or_intern(s)
        }
    }
}

/// Resolves a symbol ID back to its string
#[inline(always)]
pub fn resolve_str(id: Spur) -> Option<String> {
    match STRING_INTERNER.lock() {
        Ok(interner) => Some(interner.resolve(&id).to_string()),
        Err(poisoned) => Some(poisoned.into_inner().resolve(&id).to_string()),
    }
}

/// Gets all interned strings
#[inline(always)]
pub fn get_all_strings() -> Vec<String> {
    match STRING_INTERNER.lock() {
        Ok(interner) => interner.strings().map(|s| s.to_string()).collect(),
        Err(poisoned) => poisoned
            .into_inner()
            .strings()
            .map(|s| s.to_string())
            .collect(),
    }
}
