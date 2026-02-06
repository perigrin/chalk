# ABOUTME: Tests for Chalk::Bootstrap::Earley parser with Boolean semiring.
# ABOUTME: Layer 1: Unambiguous grammars without left recursion.
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

# Test 1: Single terminal rule (simplest case)
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('a')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('a'), "accepts 'a'");
    ok(!$parser->parse('b'), "rejects 'b'");
    ok(!$parser->parse(''), "rejects empty string");
    ok(!$parser->parse('aa'), "rejects 'aa'");
}

# Test 2: Sequence of terminals
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('a'), terminal('b')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('ab'), "accepts 'ab'");
    ok(!$parser->parse('a'), "rejects 'a'");
    ok(!$parser->parse('b'), "rejects 'b'");
    ok(!$parser->parse('ba'), "rejects 'ba'");
}

# Test 3: Single alternative (choice)
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [
                [terminal('a')],
                [terminal('b')],
            ],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('a'), "accepts 'a'");
    ok($parser->parse('b'), "accepts 'b'");
    ok(!$parser->parse('c'), "rejects 'c'");
    ok(!$parser->parse('ab'), "rejects 'ab'");
}

# Test 4: Simple nonterminal reference
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

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('a'), "accepts 'a' via nonterminal");
    ok(!$parser->parse('b'), "rejects 'b'");
}

# Test 5: Two-level nonterminal chain
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('A')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'A',
            expressions => [[reference('B')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('x')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('x'), "accepts 'x' via two-level chain");
}

# Test 6: Sequence with nonterminal
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('A'), terminal('b')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'A',
            expressions => [[terminal('a')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('ab'), "accepts 'ab'");
    ok(!$parser->parse('a'), "rejects 'a'");
    ok(!$parser->parse('b'), "rejects 'b'");
}

# Test 7: Alternative with nonterminals
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [
                [reference('A')],
                [reference('B')],
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
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('a'), "accepts 'a' via A");
    ok($parser->parse('b'), "accepts 'b' via B");
    ok(!$parser->parse('c'), "rejects 'c'");
}

# Test 8: Right recursion (simple list)
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('List')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'List',
            expressions => [
                [terminal('x'), reference('List')],
                [terminal('x')],
            ],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('x'), "accepts 'x'");
    ok($parser->parse('xx'), "accepts 'xx'");
    ok($parser->parse('xxx'), "accepts 'xxx'");
    ok($parser->parse('xxxx'), "accepts 'xxxx'");
    ok(!$parser->parse(''), "rejects empty");
    ok(!$parser->parse('xy'), "rejects 'xy'");
}

# Test 9: Regex terminal with pattern
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('[a-z]+')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('abc'), "accepts 'abc'");
    ok($parser->parse('xyz'), "accepts 'xyz'");
    ok(!$parser->parse('123'), "rejects '123'");
    ok(!$parser->parse('ABC'), "rejects 'ABC'");
}

# Test 10: Multiple sequences and alternatives
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [
                [reference('AB')],
                [reference('CD')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'AB',
            expressions => [[terminal('a'), terminal('b')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'CD',
            expressions => [[terminal('c'), terminal('d')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('ab'), "accepts 'ab'");
    ok($parser->parse('cd'), "accepts 'cd'");
    ok(!$parser->parse('ac'), "rejects 'ac'");
    ok(!$parser->parse('bd'), "rejects 'bd'");
}

done_testing();
