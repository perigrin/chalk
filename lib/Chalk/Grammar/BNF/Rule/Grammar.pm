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

        # line_list should be array of Chalk::GrammarRule objects
        my @rules = ref($line_list) eq 'ARRAY' ? $line_list->@* : ();

        # Filter out undef values (comments, blank lines)
        @rules = grep { defined($_) } @rules;

        # Group rules by LHS into hash structure
        my %rules_hash = ();
        for my $rule (@rules) {
            my $lhs = $rule->lhs;
            $rules_hash{$lhs} //= [];
            my $lhs_rules = $rules_hash{$lhs};
            push( $lhs_rules->@*, $rule );
        }

        # Extract start symbol from first rule
        my $start_symbol = @rules ? $rules[0]->lhs : '';

        # Build grammar directly with Chalk::Grammar->new()
        my $grammar = Chalk::Grammar->new(
            rules        => \%rules_hash,
            start_symbol => $start_symbol
        );
        return $grammar;
    }
}

