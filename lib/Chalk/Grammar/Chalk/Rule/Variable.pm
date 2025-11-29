# ABOUTME: Semantic action for Variable - looks up variable in scope or passes through metadata
# ABOUTME: Variable delegates to ScalarVar, ArrayVar, HashVar for variable type handling

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Variable :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Variable -> ScalarVar (lookup variable in context)
        # Variable -> ArrayVar (TODO)
        # Variable -> HashVar (TODO)
        # Variable -> ArraySize (TODO)

        # Get the variable metadata from child (ScalarVar)
        my $var_metadata = $context->child(0);

        # For now, only handle scalar variables
        # ScalarVar returns a hashref with { type => 'scalar_var', name => $identifier, sigil => '$' }
        if (ref($var_metadata) eq 'HASH' && $var_metadata->{type} eq 'scalar_var') {
            my $var_name = $var_metadata->{name};
            my $scope = $context->env->{scope};

            # Look up the variable's IR node from Scope
            # Scope stores actual node objects, not just IDs
            if ($scope) {
                my $node = $scope->lookup($var_name);
                if (defined($node) && ref($node) && $node->can('id')) {
                    # Return the node object directly
                    return $node;
                }
            }

            # Not yet defined - return metadata (for VariableDeclaration to extract name)
            return $var_metadata;
        }

        # For other variable types, pass through the metadata for now
        return $var_metadata;
    }
}

1;
