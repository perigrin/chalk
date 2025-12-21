# ABOUTME: Semantic action for Variable - looks up variable in scope or passes through metadata
# ABOUTME: Variable delegates to ScalarVar, ArrayVar, HashVar for variable type handling

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Variable :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Variable -> ScalarVar (lookup variable in context)
        # Variable -> ArrayVar (lookup array in context)
        # Variable -> HashVar (lookup hash in context)
        # Variable -> ArraySize (TODO)

        # Get the variable metadata from child (ScalarVar, ArrayVar, or HashVar)
        my $var_metadata = $context->child(0);

        # Handle all variable types that return metadata hashes
        if (ref($var_metadata) eq 'HASH') {
            my $var_type = $var_metadata->{type} // '';
            my $var_name = $var_metadata->{name};
            my $sigil = $var_metadata->{sigil};
            my $scope = $context->env->{scope};

            # Construct the full variable name with sigil for scope lookup
            my $full_name = $sigil . $var_name;

            if ($var_type eq 'scalar_var' || $var_type eq 'array_var' || $var_type eq 'hash_var') {
                # Look up the variable's IR node from Scope
                # Scope stores actual node objects, not just IDs
                if ($scope) {
                    my $node = $scope->lookup($full_name);
                    if (defined($node) && ref($node) && $node->can('id')) {
                        # Return the node object directly
                        return $node;
                    }
                }

                # Not yet defined - return metadata (for VariableDeclaration to extract name)
                return $var_metadata;
            }
        }

        # For other variable types, pass through the metadata
        return $var_metadata;
    }
}

1;
