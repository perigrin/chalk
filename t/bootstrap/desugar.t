# ABOUTME: Tests for Chalk::Bootstrap::Desugar quantifier desugaring utility.
# ABOUTME: Verifies grammar transformation that expands X+, X?, X* into helper rules.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::BNF;
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;

# Test 1: Module loads
use_ok('Chalk::Bootstrap::Desugar', 'desugar_grammar');

# Helper to create terminal symbol
sub terminal($value) {
    return Chalk::Grammar::Symbol->new(
        type  => 'terminal',
        value => $value,
    );
}

# Helper to create reference symbol
sub reference($value, $quant = undef) {
    return Chalk::Grammar::Symbol->new(
        type       => 'reference',
        value      => $value,
        quantifier => $quant,
    );
}

# Test 2: Grammar with no quantifiers passes through unchanged
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('A')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'A',
            expressions => [[terminal('a')]],
        ),
    ];

    my $result = desugar_grammar($grammar);
    is(scalar $result->@*, 2, 'no-quantifier grammar: same rule count');
    is($result->[0]->name(), 'Start', 'no-quantifier grammar: first rule name preserved');
    is($result->[1]->name(), 'A', 'no-quantifier grammar: second rule name preserved');
}

# Test 3: X+ generates helper with 2 alternatives: [X, X_plus] and [X]
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('Rule', '+')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Rule',
            expressions => [[terminal('r')]],
        ),
    ];

    my $result = desugar_grammar($grammar);
    is(scalar $result->@*, 3, 'X+ desugaring: adds one helper rule');

    # Start rule should now reference Rule_plus (no quantifier)
    my $start_syms = $result->[0]->expressions()->[0];
    is($start_syms->[0]->value(), 'Rule_plus', 'X+ desugaring: Start references Rule_plus');
    ok(!$start_syms->[0]->is_quantified(), 'X+ desugaring: reference is unquantified');

    # Helper rule: Rule_plus ::= Rule Rule_plus | Rule
    my $helper = $result->[2]; # sorted by name, appended after originals
    is($helper->name(), 'Rule_plus', 'X+ desugaring: helper rule name');
    is($helper->alternative_count(), 2, 'X+ desugaring: helper has 2 alternatives');

    # First alt: [Rule, Rule_plus]
    my $alt1 = $helper->expressions()->[0];
    is(scalar $alt1->@*, 2, 'X+ desugaring: first alt has 2 symbols');
    is($alt1->[0]->value(), 'Rule', 'X+ desugaring: first alt sym1 is Rule');
    is($alt1->[1]->value(), 'Rule_plus', 'X+ desugaring: first alt sym2 is Rule_plus');

    # Second alt: [Rule]
    my $alt2 = $helper->expressions()->[1];
    is(scalar $alt2->@*, 1, 'X+ desugaring: second alt has 1 symbol');
    is($alt2->[0]->value(), 'Rule', 'X+ desugaring: second alt sym is Rule');
}

# Test 4: X? generates helper with 2 alternatives: [X] and [] (epsilon)
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('Quantifier', '?')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Quantifier',
            expressions => [[terminal('q')]],
        ),
    ];

    my $result = desugar_grammar($grammar);
    is(scalar $result->@*, 3, 'X? desugaring: adds one helper rule');

    # Start rule should now reference Quantifier_optional
    my $start_syms = $result->[0]->expressions()->[0];
    is($start_syms->[0]->value(), 'Quantifier_optional', 'X? desugaring: Start references Quantifier_optional');
    ok(!$start_syms->[0]->is_quantified(), 'X? desugaring: reference is unquantified');

    # Helper rule: Quantifier_optional ::= Quantifier | (epsilon)
    my $helper = $result->[2];
    is($helper->name(), 'Quantifier_optional', 'X? desugaring: helper rule name');
    is($helper->alternative_count(), 2, 'X? desugaring: helper has 2 alternatives');

    # First alt: [Quantifier]
    my $alt1 = $helper->expressions()->[0];
    is(scalar $alt1->@*, 1, 'X? desugaring: first alt has 1 symbol');
    is($alt1->[0]->value(), 'Quantifier', 'X? desugaring: first alt sym is Quantifier');

    # Second alt: [] (epsilon)
    my $alt2 = $helper->expressions()->[1];
    is(scalar $alt2->@*, 0, 'X? desugaring: second alt is empty (epsilon)');
}

# Test 5: X* generates helper with 2 alternatives: [X, X_star] and [] (epsilon)
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('Foo', '*')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Foo',
            expressions => [[terminal('f')]],
        ),
    ];

    my $result = desugar_grammar($grammar);
    is(scalar $result->@*, 3, 'X* desugaring: adds one helper rule');

    # Start rule should now reference Foo_star
    my $start_syms = $result->[0]->expressions()->[0];
    is($start_syms->[0]->value(), 'Foo_star', 'X* desugaring: Start references Foo_star');

    # Helper rule: Foo_star ::= Foo Foo_star | (epsilon)
    my $helper = $result->[2];
    is($helper->name(), 'Foo_star', 'X* desugaring: helper rule name');
    is($helper->alternative_count(), 2, 'X* desugaring: helper has 2 alternatives');

    # First alt: [Foo, Foo_star]
    my $alt1 = $helper->expressions()->[0];
    is(scalar $alt1->@*, 2, 'X* desugaring: first alt has 2 symbols');
    is($alt1->[0]->value(), 'Foo', 'X* desugaring: first alt sym1 is Foo');
    is($alt1->[1]->value(), 'Foo_star', 'X* desugaring: first alt sym2 is Foo_star');

    # Second alt: [] (epsilon)
    my $alt2 = $helper->expressions()->[1];
    is(scalar $alt2->@*, 0, 'X* desugaring: second alt is empty (epsilon)');
}

# Test 6: Determinism - calling twice produces same helper rule names
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('X', '+')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'X',
            expressions => [[terminal('x')]],
        ),
    ];

    my $result1 = desugar_grammar($grammar);
    my $result2 = desugar_grammar($grammar);

    is(scalar $result1->@*, scalar $result2->@*, 'determinism: same rule count');
    for my $i (0 .. $result1->$#*) {
        is($result1->[$i]->name(), $result2->[$i]->name(),
           "determinism: rule $i has same name");
    }
}

# Test 7: Deduplication - same quantified reference in two rules creates only one helper
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('X', '+')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Other',
            expressions => [[reference('X', '+')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'X',
            expressions => [[terminal('x')]],
        ),
    ];

    my $result = desugar_grammar($grammar);
    is(scalar $result->@*, 4, 'dedup: 3 original + 1 helper (not 2)');

    # Both Start and Other should reference X_plus
    is($result->[0]->expressions()->[0]->[0]->value(), 'X_plus',
       'dedup: Start references X_plus');
    is($result->[1]->expressions()->[0]->[0]->value(), 'X_plus',
       'dedup: Other references X_plus');
}

# Test 8: Immutability - original grammar not mutated
{
    my $orig_sym = reference('Rule', '+');
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[$orig_sym]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Rule',
            expressions => [[terminal('r')]],
        ),
    ];

    my $orig_count = scalar $grammar->@*;
    my $result = desugar_grammar($grammar);

    is(scalar $grammar->@*, $orig_count, 'immutability: original grammar not modified');
    is($grammar->[0]->expressions()->[0]->[0]->quantifier(), '+',
       'immutability: original symbol still has quantifier');
    isnt($result, $grammar, 'immutability: result is a different arrayref');
}

# Test 9: Full BNF desugaring produces 12 rules (10 original + Rule_plus + Quantifier_optional)
{
    my $grammar = Chalk::Grammar::BNF->grammar();
    my $result = desugar_grammar($grammar);
    is(scalar $result->@*, 12, 'full BNF: 10 original + 2 helper = 12 rules');

    # Check helper rule names exist
    my %names = map { $_->name() => 1 } $result->@*;
    ok($names{Rule_plus}, 'full BNF: Rule_plus helper exists');
    ok($names{Quantifier_optional}, 'full BNF: Quantifier_optional helper exists');
}

# Test 10: No quantified symbols remain in desugared output
{
    my $grammar = Chalk::Grammar::BNF->grammar();
    my $result = desugar_grammar($grammar);

    my $found_quantified = false;
    for my $rule ($result->@*) {
        for my $alt ($rule->expressions()->@*) {
            for my $sym ($alt->@*) {
                if ($sym->is_quantified()) {
                    $found_quantified = true;
                    diag("Found quantified symbol: " . $sym->to_string() . " in rule " . $rule->name());
                }
            }
        }
    }
    ok(!$found_quantified, 'full BNF: no quantified symbols remain after desugaring');
}

# Integration tests with Earley parser
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;

my $bool_semiring = Chalk::Bootstrap::Semiring::Boolean->new();

# Test 11: Desugared grammar + Earley + Boolean parses simple rule
{
    my $grammar = Chalk::Grammar::BNF->grammar();
    my $desugared = desugar_grammar($grammar);

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $desugared,
        semiring => $bool_semiring,
    );

    my $input = 'Identifier ::= /[A-Za-z]+/ ;';
    ok($parser->parse($input), "integration: parses simple rule '$input'");
}

# Test 12: Parses rule with alternatives
{
    my $grammar = Chalk::Grammar::BNF->grammar();
    my $desugared = desugar_grammar($grammar);

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $desugared,
        semiring => $bool_semiring,
    );

    my $input = 'Atom ::= Identifier | InlineRegex ;';
    ok($parser->parse($input), "integration: parses rule with alternatives '$input'");
}

# Test 13: Parses multi-rule input (exercises Rule+ via Rule_plus)
{
    my $grammar = Chalk::Grammar::BNF->grammar();
    my $desugared = desugar_grammar($grammar);

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $desugared,
        semiring => $bool_semiring,
    );

    my $input = q{Identifier ::= /[A-Za-z]+/ ;
Atom ::= Identifier | InlineRegex ;};
    ok($parser->parse($input), "integration: parses multi-rule input (exercises Rule_plus)");
}

done_testing();
