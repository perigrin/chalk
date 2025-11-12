# ABOUTME: Semantic action for Variable - pass through variable metadata or complex variable operations
# ABOUTME: Variable delegates to ScalarVar, ArrayVar, HashVar, or handles complex variable operations

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Variable :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Variable -> ScalarVar (lookup variable in context)
        # Variable -> ArrayVar (TODO)
        # Variable -> HashVar (TODO)
        # Variable -> ArraySize (TODO)
        # Variable -> Variable '->' ... (TODO: complex variable operations)

        # Get the variable metadata from child (ScalarVar)
        my $var_metadata = $context->child(0);

        # For now, only handle scalar variables
        # ScalarVar returns a hashref with { type => 'scalar_var', name => $identifier, sigil => '$' }
        if (ref($var_metadata) eq 'HASH' && $var_metadata->{type} eq 'scalar_var') {
            my $var_name = $var_metadata->{name};
            my $scope = $context->env->{scope};
            my $builder = $context->env->{ir_builder};

            # Look up the variable's IR node from Scope (Chapter 3)
            if ($scope) {
                my $node_id = $scope->lookup($var_name);
                if (defined($node_id)) {
                    # Return the actual IR node object
                    return $builder->graph->get_node($node_id);
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
