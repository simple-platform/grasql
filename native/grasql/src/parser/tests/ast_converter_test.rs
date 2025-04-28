#[cfg(test)]
mod ast_converter_tests {
    use crate::parser::ast_converter::ASTConverter;
    use crate::types::OperationType;
    use graphql_query::ast::{ASTContext, Document, ParseNode};

    #[test]
    fn test_convert_query_document() {
        // Set up test GraphQL query
        let query = r#"
        {
            users {
                id
                name
            }
        }
        "#;

        // Parse the query with graphql-query
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).expect("Failed to parse query");

        // Create an AST converter and convert the document
        let mut converter = ASTConverter::new();
        let result = converter.convert_document(&document);

        // Verify the conversion worked
        assert!(result.is_ok(), "Failed to convert document");

        // Check the operation type and root fields
        let qst = result.unwrap();
        assert_eq!(qst.operation_type, OperationType::Query);
        assert_eq!(qst.root_fields.len(), 1);
        assert_eq!(qst.root_fields[0].name, "users");
        assert_eq!(qst.variables.len(), 0);
        assert_eq!(qst.fragment_definitions.len(), 0);

        // Check the nested fields
        let users_field = &qst.root_fields[0];
        assert_eq!(users_field.selection.fields.len(), 2);

        // Check field names at nested level
        let field_names: Vec<String> = users_field
            .selection
            .fields
            .iter()
            .map(|f| f.name.clone())
            .collect();

        assert!(field_names.contains(&"id".to_string()));
        assert!(field_names.contains(&"name".to_string()));
    }

    #[test]
    fn test_convert_named_query_with_variables() {
        // Set up test GraphQL query with variables
        let query = r#"
        query GetUser($id: ID!) {
            user(id: $id) {
                id
                name
                email
            }
        }
        "#;

        // Parse the query with graphql-query
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).expect("Failed to parse query");

        // Create an AST converter and convert the document
        let mut converter = ASTConverter::new();
        let result = converter.convert_document(&document);

        // Verify the conversion worked
        assert!(result.is_ok(), "Failed to convert document");

        // Check the operation type, root fields, and variables
        let qst = result.unwrap();
        assert_eq!(qst.operation_type, OperationType::Query);
        assert_eq!(qst.root_fields.len(), 1);
        assert_eq!(qst.root_fields[0].name, "user");
        assert_eq!(qst.variables.len(), 1);
        assert_eq!(qst.fragment_definitions.len(), 0);

        // Check variable definition
        let var = &qst.variables[0];
        assert_eq!(var.get("name").unwrap(), "id");
        assert_eq!(var.get("type").unwrap(), "ID!");

        // Check arguments
        let user_field = &qst.root_fields[0];
        assert!(user_field.arguments.contains_key("id"));
        assert_eq!(user_field.arguments.get("id").unwrap(), "$id");
    }

    #[test]
    fn test_convert_mutation() {
        // Set up test GraphQL mutation
        let query = r#"
        mutation CreateUser($name: String!, $email: String!) {
            createUser(name: $name, email: $email) {
                id
                name
                email
            }
        }
        "#;

        // Parse the query with graphql-query
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).expect("Failed to parse query");

        // Create an AST converter and convert the document
        let mut converter = ASTConverter::new();
        let result = converter.convert_document(&document);

        // Verify the conversion worked
        assert!(result.is_ok(), "Failed to convert document");

        // Check the operation type
        let qst = result.unwrap();
        assert_eq!(qst.operation_type, OperationType::Mutation);
        assert_eq!(qst.root_fields.len(), 1);
        assert_eq!(qst.root_fields[0].name, "createUser");
        assert_eq!(qst.variables.len(), 2);
        assert_eq!(qst.fragment_definitions.len(), 0);

        // Check variable definitions
        let var_names: Vec<String> = qst
            .variables
            .iter()
            .map(|v| v.get("name").unwrap().clone())
            .collect();

        assert!(var_names.contains(&"name".to_string()));
        assert!(var_names.contains(&"email".to_string()));

        // Check arguments
        let create_user_field = &qst.root_fields[0];
        assert!(create_user_field.arguments.contains_key("name"));
        assert!(create_user_field.arguments.contains_key("email"));
        assert_eq!(create_user_field.arguments.get("name").unwrap(), "$name");
        assert_eq!(create_user_field.arguments.get("email").unwrap(), "$email");
    }

    #[test]
    fn test_convert_deeply_nested_query() {
        // Set up test GraphQL query with deep nesting
        let query = r#"
        {
            users {
                id
                name
                posts {
                    id
                    title
                    comments {
                        id
                        text
                        author {
                            id
                            name
                        }
                    }
                }
            }
        }
        "#;

        // Parse the query with graphql-query
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).expect("Failed to parse query");

        // Create an AST converter and convert the document
        let mut converter = ASTConverter::new();
        let result = converter.convert_document(&document);

        // Verify the conversion worked
        assert!(result.is_ok(), "Failed to convert document");

        // Check the operation type and root fields
        let qst = result.unwrap();
        assert_eq!(qst.operation_type, OperationType::Query);
        assert_eq!(qst.root_fields.len(), 1);
        assert_eq!(qst.root_fields[0].name, "users");
        assert_eq!(qst.fragment_definitions.len(), 0);

        // Navigate through the nested fields
        let users_field = &qst.root_fields[0];
        let posts_field = users_field
            .selection
            .fields
            .iter()
            .find(|f| f.name == "posts")
            .expect("Posts field not found");

        let comments_field = posts_field
            .selection
            .fields
            .iter()
            .find(|f| f.name == "comments")
            .expect("Comments field not found");

        let author_field = comments_field
            .selection
            .fields
            .iter()
            .find(|f| f.name == "author")
            .expect("Author field not found");

        // Verify the deepest level has expected fields
        let author_field_names: Vec<String> = author_field
            .selection
            .fields
            .iter()
            .map(|f| f.name.clone())
            .collect();

        assert!(author_field_names.contains(&"id".to_string()));
        assert!(author_field_names.contains(&"name".to_string()));
    }

    #[test]
    fn test_handle_alias() {
        // Set up test GraphQL query with alias
        let query = r#"
        {
            userData: user(id: 1) {
                userId: id
                fullName: name
            }
        }
        "#;

        // Parse the query with graphql-query
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).expect("Failed to parse query");

        // Create an AST converter and convert the document
        let mut converter = ASTConverter::new();
        let result = converter.convert_document(&document);

        // Verify the conversion worked
        assert!(result.is_ok(), "Failed to convert document");

        // Check alias handling
        let qst = result.unwrap();
        assert_eq!(qst.root_fields.len(), 1);
        let user_field = &qst.root_fields[0];
        assert_eq!(user_field.name, "user");
        assert_eq!(user_field.alias, Some("userData".to_string()));
        assert_eq!(qst.fragment_definitions.len(), 0);

        // Check nested field aliases
        let id_field = user_field
            .selection
            .fields
            .iter()
            .find(|f| f.name == "id")
            .expect("ID field not found");

        let name_field = user_field
            .selection
            .fields
            .iter()
            .find(|f| f.name == "name")
            .expect("Name field not found");

        assert_eq!(id_field.alias, Some("userId".to_string()));
        assert_eq!(name_field.alias, Some("fullName".to_string()));
    }

    #[test]
    fn test_error_for_unsupported_subscription() {
        // Set up test GraphQL subscription
        let query = r#"
        subscription {
            newUser {
                id
                name
            }
        }
        "#;

        // Parse the query with graphql-query
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).expect("Failed to parse query");

        // Create an AST converter and convert the document
        let mut converter = ASTConverter::new();
        let result = converter.convert_document(&document);

        // Verify the conversion failed with expected error
        assert!(result.is_err());
        let err = result.err().unwrap();
        // Check that the error message mentions "subscription"
        let error_str = format!("{}", err);
        assert!(
            error_str.contains("not supported") || error_str.contains("Unsupported"),
            "Error message should indicate subscription is not supported: {}",
            error_str
        );
        assert!(
            error_str.contains("subscription") || error_str.contains("Subscription"),
            "Error message should mention subscription: {}",
            error_str
        );
    }
}
