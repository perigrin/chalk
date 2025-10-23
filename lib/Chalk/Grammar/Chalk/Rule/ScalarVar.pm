# ABOUTME: Semantic action for ScalarVar - extracts variable name from scalar syntax
# ABOUTME: ScalarVar handles $identifier and returns the variable name as metadata

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ScalarVar :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # ScalarVar -> '$' Identifier
        # ScalarVar -> '$' %SPECIAL_IDENTIFIER%

        # Child 0 is '$', child 1 is the identifier
        my $identifier_node = $context->child(1);

        # Extract the actual string - Identifier returns an array of characters
        my $identifier;
        if (ref($identifier_node) eq 'ARRAY') {
            # Join array elements to get the identifier string
            $identifier = join('', @$identifier_node);
        } else {
            $identifier = $identifier_node;
        }

        # Return a hashref with metadata about this variable
        # This will be used by Variable and VariableDeclaration
        return {
            type => 'scalar_var',
            name => $identifier,
            sigil => '$'
        };
    }
}

1;
