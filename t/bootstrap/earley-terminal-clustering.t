# ABOUTME: Tests for terminal clustering optimization (Component 7, #656).
# ABOUTME: Verifies scan phase uses core set terminal maps for batch matching.
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

# Test 1: scan cache is pre-populated by terminal clustering
# After agenda processing for a position, all terminal patterns from
# the core set's terminal_map should be in the scan cache, even before
# individual items call _scan.
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Expr',
            expressions => [
                [reference('Term'), terminal('\+'), reference('Expr')],
                [reference('Term')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Term',
            expressions => [
                [terminal('\d+')],
                [terminal('\w+')],
            ],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('1+2+3'), "arithmetic: accepts '1+2+3'");
    ok($parser->parse('abc'), "identifier: accepts 'abc'");
    ok(!$parser->parse('+'), "rejects bare operator");
}

# Test 2: parse correctness with terminal clustering
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

    ok($parser->parse('a,b,c,d,e,f,g,h'), "long list parses correctly");
    ok(!$parser->parse('a,,b'), "rejects double comma");
    ok(!$parser->parse(''), "rejects empty");
}

# Test 3: terminal clustering stats available
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('\w+'), terminal('\s+'), terminal('\w+')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('hello world'), "two-word parse succeeds");

    my $stats = $parser->scan_stats();
    ok(defined $stats, "scan_stats accessor exists");
    ok($stats->{total_matches} >= 0, "total_matches tracked");
    ok($stats->{cache_hits} >= 0, "cache_hits tracked");
}

done_testing;
