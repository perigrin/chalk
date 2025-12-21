# ABOUTME: Semantic action for HashVar - extracts variable name from hash syntax
# ABOUTME: HashVar handles %identifier and returns the variable name as metadata
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::HashVar :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # HashVar -> '%' Identifier
        # HashVar -> '%' %SPECIAL_IDENTIFIER%

        # Child 0 is '%', child 1 is the identifier
        my $identifier_node = $context->child(1);

        # Extract the actual string - Identifier returns an array of characters
        my $identifier;
        if (ref($identifier_node) eq 'ARRAY') {
            # Join array elements to get the identifier string
            $identifier = join('', $identifier_node->@*);
        } else {
            $identifier = $identifier_node;
        }

        # Return a hashref with metadata about this variable
        # This will be used by Variable and VariableDeclaration
        return {
            type => 'hash_var',
            name => $identifier,
            sigil => '%'
        };
    }
}

1;
