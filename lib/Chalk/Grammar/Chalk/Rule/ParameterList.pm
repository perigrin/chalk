# ABOUTME: Semantic action for ParameterList rule in Chalk grammar
# ABOUTME: Collects all parameters for method/function signatures into an array
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ParameterList :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # ParameterList -> Variable
        # ParameterList -> Variable WS_OPT ',' WS_OPT ParameterList
        # ParameterList -> Assignment
        # ParameterList -> Assignment WS_OPT ',' WS_OPT ParameterList
        # ParameterList ->  (empty)

        my @children = $context->children->@*;

        # Empty parameter list
        return [] if @children == 0;

        # Collect all parameters into an array
        my @params;

        # First child is always Variable or Assignment
        my $first = $context->child(0);
        if (defined $first) {
            if (ref($first) eq 'ARRAY') {
                # Already an array of params from recursion
                push @params, @$first;
            } else {
                push @params, $first;
            }
        }

        # Check for recursive case: Variable WS_OPT ',' WS_OPT ParameterList
        # child(4) would be the recursive ParameterList
        if (@children >= 5) {
            my $rest = $context->child(4);
            if (defined $rest) {
                if (ref($rest) eq 'ARRAY') {
                    push @params, @$rest;
                } else {
                    push @params, $rest;
                }
            }
        }

        return \@params;
    }
}

1;
