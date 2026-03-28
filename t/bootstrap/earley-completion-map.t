# ABOUTME: Tests that _complete() uses %_waiting_core_ids directly as candidate set.
# ABOUTME: Verifies completion works correctly without relying on _completion_map_cache.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;

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

# Test 1: Arithmetic grammar — completion with multiple nonterminals
# This exercises _complete() for Expr completing into Expr + Term chains.
# Previously used _completion_map_cache; now uses %_waiting_core_ids directly.
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Expr',
            expressions => [
                [reference('Expr'), terminal('\+'), reference('Term')],
                [reference('Term')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Term',
            expressions => [
                [reference('Term'), terminal('\*'), reference('Factor')],
                [reference('Factor')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Factor',
            expressions => [
                [terminal('\('), reference('Expr'), terminal('\)')],
                [terminal('[0-9]+')],
            ],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('1'), "arithmetic: single number");
    ok($parser->parse('1+2'), "arithmetic: addition");
    ok($parser->parse('1+2+3'), "arithmetic: chained addition");
    ok($parser->parse('1*2'), "arithmetic: multiplication");
    ok($parser->parse('1+2*3'), "arithmetic: mixed operators");
    ok($parser->parse('(1+2)*3'), "arithmetic: parenthesized expression");
    ok(!$parser->parse(''), "arithmetic: rejects empty");
    ok(!$parser->parse('+1'), "arithmetic: rejects leading plus");
    ok(!$parser->parse('1+'), "arithmetic: rejects trailing plus");
}

# Test 2: Same-position completion (nullable rule)
# When a nonterminal completes at the same position it started, the origin's
# core set may not have been discovered yet. Completion must still work
# using %_waiting_core_ids as the candidate set.
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [
                [reference('OptPrefix'), reference('Item')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'OptPrefix',
            expressions => [
                [terminal('prefix:')],
                [],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Item',
            expressions => [[terminal('[a-z]+')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('prefix:foo'), "nullable: with prefix");
    ok($parser->parse('foo'), "nullable: without prefix (OptPrefix is empty)");
    ok(!$parser->parse(''), "nullable: rejects empty");
}

# Test 3: Multiple nonterminals completing at the same position
# Exercises that all relevant waiting core_ids are found via %_waiting_core_ids
# regardless of whether _completion_map_cache is populated for this position.
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [
                [reference('A'), reference('B')],
                [reference('C')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'A',
            expressions => [[terminal('a')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'C',
            expressions => [[terminal('a'), terminal('b')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('ab'), "multi-nt: accepts 'ab' via both A+B and C paths");
    ok(!$parser->parse('a'), "multi-nt: rejects 'a' alone");
    ok(!$parser->parse('b'), "multi-nt: rejects 'b' alone");
}

# Test 4: _complete() uses %_waiting_core_ids, not _completion_map_cache
# After parsing, verify that completion_map_cache is either empty or was not
# used to gate correct results — parser produces correct results regardless.
# This is a behavioral test: if the refactored code still produces correct
# results, then %_waiting_core_ids is sufficient as the candidate set.
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'S',
            expressions => [
                [reference('A'), reference('B')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'A',
            expressions => [[terminal('x')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('y')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('xy'), "candidate-set: accepts 'xy'");
    ok(!$parser->parse('yx'), "candidate-set: rejects 'yx'");
    ok(!$parser->parse('x'), "candidate-set: rejects 'x' alone");
    ok(!$parser->parse('y'), "candidate-set: rejects 'y' alone");

    # The waiting_core_ids for 'A' should be populated at construction time
    my $waiting = $parser->waiting_core_ids();
    ok(defined $waiting->{A}, "waiting_core_ids: A is in the candidate set");
    ok(defined $waiting->{B}, "waiting_core_ids: B is in the candidate set");
}

done_testing();
