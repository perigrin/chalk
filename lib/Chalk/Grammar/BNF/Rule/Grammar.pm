package Chalk::Grammar::BNF::Rule::Grammar;
# ABOUTME: Semantic action for Grammar rule - builds final Chalk::Grammar object
# ABOUTME: Collects all grammar rules from LineList and constructs Grammar

use 5.42.0;
use experimental 'class';
use Chalk::Grammar;

class Chalk::Grammar::BNF::Rule::Grammar :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Grammar -> LineList
        # Collect all rules from LineList
        my $line_list = $context->child(0);

        # line_list should be array of rules
        my @rules = ref($line_list) eq 'ARRAY' ? @$line_list : ();

        # Filter out undef values (comments, blank lines)
        @rules = grep { defined } @rules;

        # Build grammar from collected rules
        my $grammar = Chalk::Grammar->build_grammar(rules => \@rules);
        return $grammar;
    }
}

1;
