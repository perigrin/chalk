# ABOUTME: Tests for inline handling of ? quantifiers in the Earley parser.
# ABOUTME: Verifies skip/match paths produce correct parses without desugaring ? to helper rules.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Desugar;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::SemanticAction;

# Helper to create terminal symbol
sub terminal($value) {
    return Chalk::Grammar::Symbol->new(
        type  => 'terminal',
        value => $value,
    );
}

# Helper to create reference symbol (nonterminal)
sub reference($value) {
    return Chalk::Grammar::Symbol->new(
        type  => 'reference',
        value => $value,
    );
}

# Helper to create quantified reference symbol
sub opt_reference($value) {
    return Chalk::Grammar::Symbol->new(
        type       => 'reference',
        value      => $value,
        quantifier => '?',
    );
}

# Test 1: Grammar with ? quantifier — optional present
# Start ::= 'a' B? 'c'
# B     ::= 'b'
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('a'), opt_reference('B'), terminal('c')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('abc'), "optional present: accepts 'abc'");
}

# Test 2: Grammar with ? quantifier — optional absent
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('a'), opt_reference('B'), terminal('c')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('ac'), "optional absent: accepts 'ac'");
}

# Test 3: Grammar with ? quantifier — rejection still works
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('a'), opt_reference('B'), terminal('c')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok(!$parser->parse('a'), "rejects incomplete 'a'");
    ok(!$parser->parse('ab'), "rejects incomplete 'ab'");
    ok(!$parser->parse('bc'), "rejects 'bc' (missing required 'a')");
    ok(!$parser->parse('abbc'), "rejects 'abbc' (B is optional, not repeatable)");
}

# Test 4: ? at end of rule
# Start ::= 'a' B?
# B     ::= 'b'
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('a'), opt_reference('B')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('ab'), "optional at end present: accepts 'ab'");
    ok($parser->parse('a'), "optional at end absent: accepts 'a'");
    ok(!$parser->parse('b'), "rejects 'b'");
}

# Test 5: ? at start of rule
# Start ::= B? 'a'
# B     ::= 'b'
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[opt_reference('B'), terminal('a')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('ba'), "optional at start present: accepts 'ba'");
    ok($parser->parse('a'), "optional at start absent: accepts 'a'");
    ok(!$parser->parse('b'), "rejects 'b'");
}

# Test 6: Multiple optionals in one rule
# Start ::= A? 'x' B?
# A     ::= 'a'
# B     ::= 'b'
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[opt_reference('A'), terminal('x'), opt_reference('B')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'A',
            expressions => [[terminal('a')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('axb'), "both optionals present: accepts 'axb'");
    ok($parser->parse('ax'), "only A present: accepts 'ax'");
    ok($parser->parse('xb'), "only B present: accepts 'xb'");
    ok($parser->parse('x'), "both absent: accepts 'x'");
    ok(!$parser->parse('ab'), "rejects 'ab' (missing 'x')");
}

# Test 7: Desugar.pm no longer creates _opt helper rules for ?
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('a'), opt_reference('B'), terminal('c')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
    ];

    my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar($grammar);

    # Should have exactly 2 rules (Start + B), no B_opt helper
    is(scalar $desugared->@*, 2, "desugar does not create _opt helper for ? quantifier");

    # The ? symbol should still be in the desugared grammar (pass-through)
    my $start = $desugared->[0];
    my $sym = $start->expressions()->[0][1];
    ok($sym->is_quantified(), "? symbol preserved in desugared grammar");
    is($sym->quantifier(), '?', "quantifier is still '?'");
}

# Test 8: SemanticAction produces correct Context tree with placeholder for absent optional
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('a'), opt_reference('B'), terminal('c')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    # Optional absent: 'ac'
    my $value = $parser->parse_value('ac');
    ok(defined $value, "SemanticAction parse_value returns defined for 'ac'");

    # The context should have children for: 'a', placeholder, 'c'
    # The placeholder represents the absent B?
    my @children = $value->children()->@*;
    # Flatten the multiply tree to count significant leaves (non-one() singletons)
    my @leaves;
    my $collect;
    $collect = sub($ctx) {
        if ($ctx->children()->@* == 0) {
            push @leaves, $ctx;
        } else {
            for my $child ($ctx->children()->@*) {
                $collect->($child);
            }
        }
    };
    $collect->($value);
    # Filter out the one() singleton: it has undef focus, no rule, no children
    my @significant = grep {
        defined $_->extract() || defined $_->rule()
    } @leaves;
    # We expect 3 significant leaves: 'a' scan, placeholder (B_opt rule), 'c' scan
    is(scalar @significant, 3,
        "absent optional produces 3 significant leaf contexts (a, placeholder, c)");
    is($significant[0]->extract(), 'a', "first leaf is 'a'");
    ok(!defined $significant[1]->extract(), "second leaf (placeholder) has undef focus");
    is($significant[1]->rule(), 'B_opt', "placeholder has B_opt rule name");
    is($significant[2]->extract(), 'c', "third leaf is 'c'");

    # Optional present: 'abc'
    my $value2 = $parser->parse_value('abc');
    $semiring->reset_cache();
    ok(defined $value2, "SemanticAction parse_value returns defined for 'abc'");
}

done_testing;
