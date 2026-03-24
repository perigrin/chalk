# ABOUTME: Tests for the chart representation refactor (Component 3, #652).
# ABOUTME: Verifies chart stores values directly, not [$item, $alt_idx] wrappers.
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

# Test 1: _make_item and _advance_item should no longer exist
# After the chart representation refactor, items are not allocated as hashrefs.
# The chart stores values directly: $chart[$pos][$core_id]{$origin} = $value.
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

    ok(!$parser->can('_make_item'), "_make_item method removed after refactor");
    ok(!$parser->can('_advance_item'), "_advance_item method removed after refactor");
}

# Test 2: Parse correctness preserved — simple terminal
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

    ok($parser->parse('a'), "simple terminal: accepts 'a'");
    ok(!$parser->parse('b'), "simple terminal: rejects 'b'");
}

# Test 3: Parse correctness preserved — sequence with nonterminals
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('A'), reference('B')]],
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

    ok($parser->parse('ab'), "sequence: accepts 'ab'");
    ok(!$parser->parse('ba'), "sequence: rejects 'ba'");
}

# Test 4: Parse correctness preserved — alternatives
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

    ok($parser->parse('a'), "alternatives: accepts 'a'");
    ok($parser->parse('b'), "alternatives: accepts 'b'");
    ok(!$parser->parse('c'), "alternatives: rejects 'c'");
}

# Test 5: parse_value returns non-undef for accepted input
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('hello')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    my $value = $parser->parse_value('hello');
    ok(defined $value, "parse_value returns defined value");
    ok(!$semiring->is_zero($value), "parse_value returns non-zero value");
}

# Test 6: Left-recursive parse correctness preserved
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

    ok($parser->parse('a,b,c'), "left-recursive: accepts 'a,b,c'");
    ok(!$parser->parse('a,,b'), "left-recursive: rejects double comma");
}

# Test 7: Right-recursive parse correctness preserved (Leo path)
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

    ok($parser->parse('a,b,c'), "right-recursive: accepts 'a,b,c'");

    # Stress test: 1000 items should complete quickly with Leo
    my $input = join(',', ('w') x 1000);
    my $start = time();
    my $result = $parser->parse($input);
    my $elapsed = time() - $start;

    ok($result, "right-recursive 1000 items: parses successfully");
    ok($elapsed < 3, "right-recursive 1000 items: < 3s (got ${elapsed}s)");
}

done_testing;
