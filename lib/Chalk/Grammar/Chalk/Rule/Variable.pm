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
            my $builder = $context->env->{ir_builder};

            # Look up the variable's IR node from the context (Chapter 3)
            my $node_id = $builder->lookup_variable($var_name);

            # If found, return the IR node (variable reference)
            # If not found, return metadata (for VariableDeclaration to extract name)
            return $node_id if defined($node_id);
            return $var_metadata;  # Not yet defined - return metadata for declaration
        }

        # For other variable types, pass through the metadata for now
        return $var_metadata;
    }
}

1;
