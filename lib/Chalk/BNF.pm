# ABOUTME: BNF grammar parser using semantic actions architecture
# ABOUTME: Primary API: parse_bnf() - parses BNF content and returns Chalk::Grammar
package Chalk::BNF;
use 5.42.0;
use utf8;
use Chalk::Grammar;
use Chalk::Grammar::BNF;
use Chalk::Parser;
use Chalk::Semiring::Semantic;

sub parse_bnf($bnf_content) {
    # Parse BNF using hand-coded BNF grammar with semantic actions
    # Returns Chalk::Grammar object directly from parsing
    #
    # This parser fully supports all BNF syntax including grammar rules,
    # terminals, nonterminals, pattern definitions, and comments.

    my $bnf_grammar = Chalk::Grammar::BNF->grammar;

    # Create environment with pattern table for storing %NAME% definitions
    my %env = (
        patterns => {}  # Pattern name => compiled regex
    );

    my $semiring = Chalk::Semiring::Semantic->new(
        env => \%env,
        grammar => $bnf_grammar
    );

    my $parser = Chalk::Parser->new(
        grammar => $bnf_grammar,
        semiring => $semiring
    );

    my $result = $parser->parse_string($bnf_content);

    # Extract Grammar object from semantic result
    return $result ? $result->context->extract : undef;
}

sub build_chalk_grammar($bnf_content, $start_symbol = undef) {
    # Use new semantic actions parser
    my $grammar = parse_bnf($bnf_content);

    return undef unless $grammar;

    # If start symbol specified and different from current, rebuild with correct start
    if (defined $start_symbol && $grammar->start_symbol ne $start_symbol) {
        # Extract all rules and rebuild with specified start symbol
        my %all_rules = %{$grammar->rules};

        # Reorder to ensure start symbol is first
        my @rules_array;

        # Add start symbol rules first
        if (exists $all_rules{$start_symbol}) {
            for my $rule (@{$all_rules{$start_symbol}}) {
                push @rules_array, [$start_symbol, $rule->rhs];
            }
        }

        # Add all other rules
        for my $lhs (sort grep { $_ ne $start_symbol } keys %all_rules) {
            for my $rule (@{$all_rules{$lhs}}) {
                push @rules_array, [$lhs, $rule->rhs];
            }
        }

        return Chalk::Grammar->build_grammar(rules => \@rules_array);
    }

    return $grammar;
}

1;
