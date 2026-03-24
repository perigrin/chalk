# ABOUTME: Tests for relative distance chart representation (Component 6, #655).
# ABOUTME: Verifies chart uses arrays for origin dimension and distance vectors are small.
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
my $parser = Chalk::Bootstrap::Earley->new(
    grammar  => $grammar,
    semiring => $semiring,
);

# Test 1: chart origin dimension is now an array (not a hash)
# After the refactor, $chart[$pos][$core_id] should be an ARRAY ref
# containing values indexed by relative distance, not a HASH ref
# keyed by absolute origin.
{
    ok($parser->parse('a,b,c'), "parse succeeds");

    # Access the chart structure to verify array representation.
    # The chart_origin_type method returns 'ARRAY' or 'HASH' based on
    # the internal representation.
    my $origin_type = $parser->chart_origin_type();
    is($origin_type, 'ARRAY', "chart origin dimension is array (relative distances)");
}

# Test 2: distance vectors contain small relative integers
{
    $parser->reset_parse_state();
    ok($parser->parse('a,b,c,d,e'), "parse long list");

    my $dist_stats = $parser->distance_stats();
    ok(defined $dist_stats, "distance_stats accessor exists");
    ok($dist_stats->{max_distance} >= 0, "max distance is non-negative");
    # For a comma-separated list, relative distances should be small
    # (most items have origin close to current position)
    ok($dist_stats->{max_distance} < 20,
        "max distance is small ($dist_stats->{max_distance} < 20)");
}

# Test 3: set registry records (core_set_id, distance_vector_hash) pairs
{
    my $set_registry = $parser->set_registry();
    ok(defined $set_registry, "set_registry accessor exists");
    ok(ref($set_registry) eq 'HASH', "set_registry is a hashref");

    my $count = scalar keys $set_registry->%*;
    ok($count > 0, "set_registry has entries ($count)");
}

# Test 4: parse correctness preserved across all patterns
{
    $parser->reset_parse_state();
    ok($parser->parse('x'), "single item");
    $parser->reset_parse_state();
    ok($parser->parse('x,y'), "two items");
    $parser->reset_parse_state();
    ok($parser->parse('a,b,c,d,e,f'), "six items");
    $parser->reset_parse_state();
    ok(!$parser->parse(''), "rejects empty");
    $parser->reset_parse_state();
    ok(!$parser->parse('a,'), "rejects trailing comma");
}

# Test 5: right-recursive correctness with relative distances
{
    my $rr_grammar = [
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

    my $rr_parser = Chalk::Bootstrap::Earley->new(
        grammar  => $rr_grammar,
        semiring => $semiring,
    );

    ok($rr_parser->parse('a,b,c'), "right-recursive: accepts 'a,b,c'");
    ok(!$rr_parser->parse('a,,b'), "right-recursive: rejects 'a,,b'");
}

# Test 6: parse_value returns correct value (not just boolean)
{
    $parser->reset_parse_state();
    my $value = $parser->parse_value('a,b');
    ok(defined $value, "parse_value returns defined result");
    ok(!$semiring->is_zero($value), "parse_value returns non-zero");
}

done_testing;
