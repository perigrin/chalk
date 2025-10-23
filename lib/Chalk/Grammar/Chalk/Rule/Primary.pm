# ABOUTME: Semantic action for Primary - pass through child value or build primary expression
# ABOUTME: Primary handles literals, variables, function calls, and other primary expressions

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Primary :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Primary -> Literal (pass-through)
        # Primary -> Variable (creates Load node)
        # Primary -> Identifier (TODO: bareword)
        # Primary -> Identifier '(' WS_OPT ExpressionList WS_OPT ')' (TODO: function call)
        # Primary -> ... (many other alternatives)

        my $child = $context->child(0);

        # Check if child is a variable metadata hashref (from ScalarVar)
        if (ref($child) eq 'HASH' && $child->{type} eq 'scalar_var') {
            # This is a variable usage - create Load node
            my $builder = $context->env->{ir_builder};
            return $child unless $builder;  # Pass through if no builder

            return $builder->build_load_node($child->{name});
        }

        # Otherwise pass through
        return $child;
    }
}

1;
