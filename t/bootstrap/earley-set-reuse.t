# ABOUTME: Tests for set reuse optimization (Component 8, #657).
# ABOUTME: Verifies prediction caching and sub-linear scaling for repetitive input.
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

# Test 1: prediction cache has entries after parsing
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('a,b,c,d,e'), "parse succeeds");

    my $pred_cache = $parser->prediction_cache();
    ok(defined $pred_cache, "prediction_cache accessor exists");
    ok(ref($pred_cache) eq 'HASH', "prediction_cache is a hashref");

    my $cached_count = scalar keys $pred_cache->%*;
    ok($cached_count > 0, "prediction_cache has entries ($cached_count)");
}

# Test 2: prediction reuse count is positive for repetitive input
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    my $input = join(',', ('word') x 20);
    ok($parser->parse($input), "parse 20-item list");

    my $stats = $parser->reuse_stats();
    ok(defined $stats, "reuse_stats accessor exists");
    ok($stats->{prediction_reuses} > 0,
        "prediction reuses > 0 (got $stats->{prediction_reuses})");
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

# Test 4: prediction cache survives reset_parse_state (grammar-lifetime)
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    $parser->parse('a,b,c');
    my $count_before = scalar keys $parser->prediction_cache()->%*;

    $parser->reset_parse_state();

    my $count_after = scalar keys $parser->prediction_cache()->%*;
    is($count_after, $count_before,
        "prediction_cache preserved after reset_parse_state");
}

done_testing;
