# ABOUTME: Pre-parse grammar transformation that expands quantified symbols into helper rules.
# ABOUTME: Desugars X+, X?, X* so the Earley parser never sees quantifiers.
use 5.42.0;
use utf8;

package Chalk::Bootstrap::Desugar;

use Exporter 'import';
our @EXPORT_OK = ('desugar_grammar');

use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;

# Transform a grammar by expanding quantified symbols into helper rules.
# Returns a new grammar arrayref (does NOT mutate input).
sub desugar_grammar($grammar) {
    my %helpers;       # name => Chalk::Grammar::Rule (deduplication)
    my @new_rules;

    for my $rule ($grammar->@*) {
        my @new_expressions;

        for my $alt ($rule->expressions()->@*) {
            my @new_alt;

            for my $sym ($alt->@*) {
                if ($sym->is_quantified()) {
                    my $helper_name = _helper_name($sym->value(), $sym->quantifier());

                    # Create helper rule if not already seen
                    if (!exists $helpers{$helper_name}) {
                        $helpers{$helper_name} = _make_helper_rule(
                            $helper_name, $sym->value(), $sym->quantifier(), $sym->type(),
                        );
                    }

                    # Replace quantified symbol with plain reference to helper
                    push @new_alt, Chalk::Grammar::Symbol->new(
                        type  => 'reference',
                        value => $helper_name,
                    );
                } else {
                    # Non-quantified symbols pass through as-is
                    push @new_alt, $sym;
                }
            }

            push @new_expressions, \@new_alt;
        }

        # Build a new rule with the (possibly updated) expressions
        push @new_rules, Chalk::Grammar::Rule->new(
            name        => $rule->name(),
            expressions => \@new_expressions,
        );
    }

    # Append helper rules sorted by name for determinism
    for my $name (sort keys %helpers) {
        push @new_rules, $helpers{$name};
    }

    return \@new_rules;
}

# Generate deterministic helper rule name from base symbol and quantifier.
sub _helper_name($base, $quant) {
    my %suffix = (
        '+' => 'plus',
        '?' => 'optional',
        '*' => 'star',
    );
    return "${base}_$suffix{$quant}";
}

# Build a Chalk::Grammar::Rule for a desugared quantifier.
sub _make_helper_rule($name, $base, $quant, $type) {
    my $base_sym = Chalk::Grammar::Symbol->new(type => $type, value => $base);
    my $self_ref = Chalk::Grammar::Symbol->new(type => 'reference', value => $name);

    my @expressions;

    if ($quant eq '+') {
        # X_plus ::= X X_plus | X
        @expressions = (
            [$base_sym, $self_ref],
            [$base_sym],
        );
    } elsif ($quant eq '?') {
        # X_optional ::= X | (epsilon)
        @expressions = (
            [$base_sym],
            [],
        );
    } elsif ($quant eq '*') {
        # X_star ::= X X_star | (epsilon)
        @expressions = (
            [$base_sym, $self_ref],
            [],
        );
    }

    return Chalk::Grammar::Rule->new(
        name        => $name,
        expressions => \@expressions,
    );
}

true;
