# ABOUTME: Semantic action for Atom - atomic expressions (literals, variables, identifiers, yada-yada)
# ABOUTME: Atoms are base cases for expression evaluation - handles variable Load nodes

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Atom :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Atom -> Literal
        # Atom -> Variable
        # Atom -> Identifier
        # Atom -> '...'

        my $child = $context->child(0);

        # Check if child is a variable metadata hashref (from ScalarVar)
        if (ref($child) eq 'HASH' && $child->{type} eq 'scalar_var') {
            # This is a variable usage - create Load node
            my $builder = $context->env->{ir_builder};
            return $child unless $builder;  # Pass through if no builder

            return $builder->build_load_node($child->{name});
        }

        # Otherwise pass through (Literal, Identifier, yada-yada)
        return $child;
    }
}

1;
