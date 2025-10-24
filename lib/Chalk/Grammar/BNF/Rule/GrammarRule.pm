# ABOUTME: Semantic action for GrammarRule - creates Chalk::GrammarRule objects
# ABOUTME: Extracts nonterminal name and RHS elements and wraps in GrammarRule object

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::BNF::Rule::GrammarRule :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Two alternatives:
        # 1. GrammarRule -> Nonterminal WS '->' WS RHS Comment (6 children)
        # 2. GrammarRule -> Nonterminal WS '->' WS RHS (5 children)
        # Children: [0] = LHS nonterminal name (string)
        #           [1] = whitespace (ignore)
        #           [2] = '->' (ignore)
        #           [3] = whitespace (ignore)
        #           [4] = RHS (array of symbols)
        #           [5] = optional inline comment (ignore if present)

        my $children = $context->children();
        my @children = map { $_->extract() } $children->@*;

        # Extract LHS (nonterminal name)
        my $lhs = $children[0];

        # Extract RHS (array of symbols)
        # Inline comment at [5] is automatically ignored (only present in 6-child case)
        my $rhs = $children[4] // [];
        $rhs = [] unless ref($rhs) eq 'ARRAY';

        # Try to load custom semantic action class for this rule
        # Determine grammar name from context (if available)
        my $grammar_name = $context->env->{grammar_name} // '';
        my $rule_class;

        if ($grammar_name) {
            # Try loading Chalk::Grammar::{Name}::Rule::{RuleName}
            $rule_class = "Chalk::Grammar::${grammar_name}::Rule::${lhs}";

            # Try to load the class
            eval "require $rule_class; 1";
            if ($@) {
                # Class doesn't exist or failed to load, use base class
                undef $rule_class;
            }
        }

        # If custom class exists, use it; otherwise use base Chalk::GrammarRule
        my $class = $rule_class // 'Chalk::GrammarRule';

        return $class->new(
            lhs         => $lhs,
            rhs         => $rhs,
            probability => 1.0
        );
    }
}

