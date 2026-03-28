# ABOUTME: Tests for relative distance chart representation.
# ABOUTME: Verifies chart uses arrays for origin dimension and parsing is correct.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;

sub terminal($value) {
    return Chalk::Grammar::Symbol->new(
        type  => 'terminal',
        value => $value,
    );
}

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

# Test 1: chart origin dimension is array (relative distances)
{
    ok($parser->parse('a,b,c'), "parse succeeds");
    my $origin_type = $parser->chart_origin_type();
    is($origin_type, 'ARRAY', "chart origin dimension is array (relative distances)");
}

# Test 2: parse correctness preserved across all patterns
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

# Test 3: right-recursive correctness with relative distances
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

# Test 4: parse_value returns correct value
{
    $parser->reset_parse_state();
    my $value = $parser->parse_value('a,b');
    ok(defined $value, "parse_value returns defined result");
    ok(!$semiring->is_zero($value), "parse_value returns non-zero");
}

done_testing;
