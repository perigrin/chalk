# ABOUTME: Tests for Leo optimization in the Earley parser.
# ABOUTME: Verifies Leo items enable O(n) parsing for left- and right-recursive grammars.
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

# Test 1: Left-recursive chain — correctness
# Grammar: List ::= Item | List Comma Item
#          Item ::= /\w+/
#          Comma ::= /,/
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'List',
            expressions => [
                [reference('Item')],
                [reference('List'), reference('Comma'), reference('Item')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Item',
            expressions => [[terminal('\w+')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Comma',
            expressions => [[terminal(',')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('a'), "left-recursive: single item");
    ok($parser->parse('a,b'), "left-recursive: two items");
    ok($parser->parse('a,b,c'), "left-recursive: three items");
    ok(!$parser->parse(''), "left-recursive: rejects empty");
    ok(!$parser->parse('a,'), "left-recursive: rejects trailing comma");
    ok(!$parser->parse(',a'), "left-recursive: rejects leading comma");
}

# Test 2: Left-recursive chain — performance scaling
# 100 comma-separated words should parse in < 2 seconds with Leo items.
# Without Leo, this is O(n^2) in the number of items in the list.
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'List',
            expressions => [
                [reference('Item')],
                [reference('List'), reference('Comma'), reference('Item')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Item',
            expressions => [[terminal('\w+')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Comma',
            expressions => [[terminal(',')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    my $input = join(',', ('word') x 2000);
    my $start = time();
    my $result = $parser->parse($input);
    my $elapsed = time() - $start;

    ok($result, "left-recursive 2000 items: parses successfully");
    ok($elapsed < 3, "left-recursive 2000 items: completes in < 3s (got ${elapsed}s)");
}

# Test 3: Right-recursive chain — correctness and performance
# Grammar: Chain ::= Item | Item Comma Chain
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Chain',
            expressions => [
                [reference('Item')],
                [reference('Item'), reference('Comma'), reference('Chain')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Item',
            expressions => [[terminal('\w+')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Comma',
            expressions => [[terminal(',')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('a'), "right-recursive: single item");
    ok($parser->parse('a,b'), "right-recursive: two items");
    ok($parser->parse('a,b,c'), "right-recursive: three items");

    my $input = join(',', ('word') x 2000);
    my $start = time();
    my $result = $parser->parse($input);
    my $elapsed = time() - $start;

    ok($result, "right-recursive 2000 items: parses successfully");
    ok($elapsed < 3, "right-recursive 2000 items: completes in < 3s (got ${elapsed}s)");
}

# Test 4: Leo items don't interfere with ambiguous grammars
# Grammar where a nonterminal has multiple waiting items (Leo should NOT activate)
# Ambiguous: S ::= A B | A C ; A ::= /a/ ; B ::= /b/ ; C ::= /b/
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'S',
            expressions => [
                [reference('A'), reference('B')],
                [reference('A'), reference('C')],
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
            expressions => [[terminal('b')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('ab'), "ambiguous grammar: still parses correctly with Leo");
    ok(!$parser->parse('ac'), "ambiguous grammar: rejects non-matching");
}

# Test 5: Deeply left-recursive with 500 items — stress test
# This would be very slow without Leo (quadratic), fast with Leo (linear)
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'List',
            expressions => [
                [reference('Item')],
                [reference('List'), reference('Comma'), reference('Item')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Item',
            expressions => [[terminal('\w+')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Comma',
            expressions => [[terminal(',')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    my $input = join(',', ('x') x 5000);
    my $start = time();
    my $result = $parser->parse($input);
    my $elapsed = time() - $start;

    ok($result, "left-recursive 5000 items: parses successfully");
    ok($elapsed < 5, "left-recursive 5000 items: completes in < 5s (got ${elapsed}s)");
}

done_testing;
