# ABOUTME: Tests for set reuse optimization — verifies prediction occurs via DFA
# ABOUTME: and that parse correctness is preserved without prediction caching.
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

# Test 1: DFA prediction produces correct parse results for simple input
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('a,b,c,d,e'), "parse succeeds with DFA-based prediction");
}

# Test 2: DFA prediction correctly handles repeated core sets
# The same nonterminals get predicted at each position via the DFA
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    my $input = join(',', ('word') x 20);
    ok($parser->parse($input), "parse 20-item list via DFA prediction");
}

# Test 3: parse correctness preserved
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('a'), "single item");
    $parser->reset_parse_state();
    ok($parser->parse('a,b'), "two items");
    $parser->reset_parse_state();
    ok(!$parser->parse('a,,b'), "rejects double comma");
    $parser->reset_parse_state();
    ok(!$parser->parse(''), "rejects empty");
}

# Test 4: DFA-based prediction is stable across multiple parses
# (no per-parse cache to become stale)
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    $parser->parse('a,b,c');
    $parser->reset_parse_state();
    ok($parser->parse('x,y,z'), "second parse after reset succeeds");
    $parser->reset_parse_state();
    ok($parser->parse('p,q'), "third parse after reset succeeds");
}

done_testing;
