//! Variable processor for handling GraphQL variables
//!
//! This module processes GraphQL variables, converting them from JSON input
//! to a format usable by GraSQL.

use graphql_query::ast::{ASTContext, Document};
use graphql_query::json::{ast_variables_from_value, value_from_ast_variables};
use serde_json::Value;
use std::collections::HashMap;

use super::error::{Error, Result};

/// Processor for GraphQL variables
pub struct VariableProcessor;

impl VariableProcessor {
    /// Creates a new variable processor
    pub fn new() -> Self {
        VariableProcessor
    }

    /// Processes variables from a GraphQL document and JSON input
    ///
    /// # Arguments
    ///
    /// * `document` - The parsed GraphQL document
    /// * `variables_value` - The JSON value containing variable values
    ///
    /// # Returns
    ///
    /// * `Result<HashMap<String, String>>` - Map of variable names to values or an error
    pub fn process_variables(
        &self,
        document: &Document,
        variables_value: &Value,
    ) -> Result<HashMap<String, String>> {
        // Get the operation from the document
        let operation = document
            .operation(None)
            .map_err(|e| Error::ParsingError(format!("Failed to get operation: {}", e)))?;

        // Create empty variable map if variables_value is null or not an object
        if variables_value.is_null() || !variables_value.is_object() {
            return Ok(HashMap::new());
        }

        // Create a new AST context for variable processing
        let ctx = ASTContext::new();

        // Convert JSON variables to GraphQL variables
        let ast_variables = match ast_variables_from_value(
            &ctx,
            variables_value,
            &operation.variable_definitions,
        ) {
            Ok(vars) => vars,
            Err(e) => {
                return Err(Error::VariableError(format!(
                    "Failed to convert variables: {}",
                    e
                )))
            }
        };

        // Convert to HashMap<String, String> for GraSQL
        let mut variable_map = HashMap::new();

        // Convert GraphQL variables to JSON map
        let json_map = value_from_ast_variables(&ast_variables);

        // Convert JSON map to HashMap<String, String>
        for (key, value) in json_map.iter() {
            // Convert value to string representation
            let value_str = match serde_json::to_string(value) {
                Ok(s) => s,
                Err(e) => {
                    return Err(Error::VariableError(format!(
                        "Failed to stringify variable {}: {}",
                        key, e
                    )))
                }
            };

            variable_map.insert(key.clone(), value_str);
        }

        Ok(variable_map)
    }
}
