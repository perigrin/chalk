# ABOUTME: Semantic action for Expression - pass through child value or convert Variable to Load node
# ABOUTME: Expression delegates to many alternatives; converts Variable metadata to Load nodes for IR

use 5.42.0;
use experimental 'class';
use Chalk::Grammar;  # Provides Chalk::GrammarRule base class

class Chalk::Grammar::Chalk::Rule::Expression :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Expression -> Literal
        # Expression -> Variable
        # Expression -> Identifier
        # Expression -> YaddaYadda
        # Expression -> FunctionCall
        # Expression -> Assignment (and many other operators)
        # Expression -> '(' WS_OPT Expression WS_OPT ')' (parenthesized)

        my $first_child = $context->child(0);

        # Handle parenthesized expressions: '(' WS_OPT Expression WS_OPT ')'
        # When first child is '(', the actual expression is at child(2)
        # This allows (1 + 2) * 3 to work correctly
        if (defined $first_child && $first_child eq '(') {
            return $context->child(2);
        }

        my $child = $first_child;

        # Check if child is a variable metadata hashref (from ScalarVar via Variable)
        # Variables in expression context need to be converted to Load nodes
        if (ref($child) eq 'HASH' && $child->{type} eq 'scalar_var') {
            # Look up variable from Scope (handles nested scopes including loops)
            my $scope = $context->env->{scope};
            if ($scope) {
                my $var_name = $child->{name};
                my $node = $scope->lookup($var_name);

                # Return the node if found, otherwise pass through metadata
                return $node if defined($node) && ref($node) && $node->can('id');
            }

            # Pass through metadata if no scope or variable not found
            return $child;
        }

        # Otherwise pass through (Literal, Identifier, YaddaYadda, operators, etc.)
        return $child;
    }
}

1;
