# ABOUTME: Pre-parse grammar transformation that expands quantified symbols into helper rules.
# ABOUTME: Desugars X+ and X* into helper rules; X? passes through for inline parser handling.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::Desugar {

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
                if ($sym->is_quantified() && $sym->quantifier() ne '?') {
                    my $helper_name = _helper_name($sym->value(), $sym->quantifier());

                    # Create helper rule(s) if not already seen
                    if (!exists $helpers{$helper_name}) {
                        _create_helpers(
                            \%helpers, $sym->value(), $sym->quantifier(), $sym->type(),
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
        '?' => 'opt',
        '*' => 'star',
    );
    die "Unknown quantifier '$quant' on symbol '$base'"
        unless exists $suffix{$quant};
    return "${base}_$suffix{$quant}";
}

# Create helper rule(s) for a desugared quantifier and register them in %helpers.
# Per PRD: X+ generates both X_plus and X_star; X* and X? each generate one rule.
sub _create_helpers($helpers, $base, $quant, $type) {
    my $base_sym = Chalk::Grammar::Symbol->new(type => $type, value => $base);

    die "Unknown quantifier '$quant' on symbol '$base'"
        unless $quant eq '+' || $quant eq '?' || $quant eq '*';

    if ($quant eq '+') {
        # X_plus ::= X X_star (single alternative, reuses X_star)
        my $star_name = _helper_name($base, '*');
        my $plus_name = _helper_name($base, '+');

        # Create X_star if not already present (e.g., from an explicit X* elsewhere)
        if (!exists $helpers->{$star_name}) {
            my $star_ref = Chalk::Grammar::Symbol->new(type => 'reference', value => $star_name);
            $helpers->{$star_name} = Chalk::Grammar::Rule->new(
                name        => $star_name,
                expressions => [
                    [$base_sym, $star_ref],
                    [],
                ],
            );
        }

        my $star_ref = Chalk::Grammar::Symbol->new(type => 'reference', value => $star_name);
        $helpers->{$plus_name} = Chalk::Grammar::Rule->new(
            name        => $plus_name,
            expressions => [
                [$base_sym, $star_ref],
            ],
        );
    } elsif ($quant eq '?') {
        # X_opt ::= X | (epsilon)
        my $opt_name = _helper_name($base, '?');
        $helpers->{$opt_name} = Chalk::Grammar::Rule->new(
            name        => $opt_name,
            expressions => [
                [$base_sym],
                [],
            ],
        );
    } elsif ($quant eq '*') {
        # X_star ::= X X_star | (epsilon)
        my $star_name = _helper_name($base, '*');
        my $star_ref = Chalk::Grammar::Symbol->new(type => 'reference', value => $star_name);
        $helpers->{$star_name} = Chalk::Grammar::Rule->new(
            name        => $star_name,
            expressions => [
                [$base_sym, $star_ref],
                [],
            ],
        );
    }
}
}
