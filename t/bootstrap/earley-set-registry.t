# ABOUTME: Tests for distance vector set registry — measures structural reuse
# ABOUTME: across parse positions by computing set_keys from (core_id, rel_dist) pairs.
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

# Repetitive grammar: identical statements separated by semicolons
my $grammar = [
    Chalk::Grammar::Rule->new(
        name        => 'Program',
        expressions => [
            [reference('Statement')],
            [reference('Program'), terminal(';'), reference('Statement')],
        ],
    ),
    Chalk::Grammar::Rule->new(
        name        => 'Statement',
        expressions => [[terminal('\\w+'), terminal('='), terminal('\\d+')]],
    ),
];

my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();

# Test 1: set_reuse_stats accessor exists and returns a hashref
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    my $stats = $parser->set_reuse_stats();
    ok(defined $stats, "set_reuse_stats returns a defined value");
    is(ref $stats, 'HASH', "set_reuse_stats returns a hashref");
}

# Test 2: after parsing, stats contain unique_sets and reuse_hits
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('x=1'), "parse single statement");

    my $stats = $parser->set_reuse_stats();
    ok(exists $stats->{unique_sets}, "stats has unique_sets key");
    ok(exists $stats->{reuse_hits}, "stats has reuse_hits key");
    cmp_ok($stats->{unique_sets}, '>', 0, "unique_sets > 0 after parse");
}

# Test 3: repetitive input produces reuse hits
# "x=1;y=2;z=3" has three identical statements — the positions after
# each semicolon should have the same DFA state and similar distance
# vectors, producing set_key collisions.
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('x=1;y=2;z=3;a=4;b=5'), "parse 5 repetitive statements");

    my $stats = $parser->set_reuse_stats();
    cmp_ok($stats->{reuse_hits}, '>', 0,
        "repetitive input produces set reuse hits");
    cmp_ok($stats->{reuse_hits}, '>=', 2,
        "at least 2 reuse hits for 5 identical statements");

    # Reuse rate should be meaningful
    my $total = $stats->{unique_sets} + $stats->{reuse_hits};
    cmp_ok($total, '>', 0, "total positions tracked > 0");
}

# Test 4: stats reset between parses
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    $parser->parse('x=1;y=2;z=3');
    my $stats1 = { $parser->set_reuse_stats()->%* };  # copy

    $parser->reset_parse_state();
    $parser->parse('a=1');
    my $stats2 = $parser->set_reuse_stats();

    # After reset + re-parse, stats should reflect only the second parse
    cmp_ok($stats2->{unique_sets}, '<', $stats1->{unique_sets},
        "stats reset between parses - fewer unique sets for shorter input");
}

done_testing;
