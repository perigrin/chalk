# ABOUTME: Tests that error recovery does not false-trigger on scanner-skipped positions.
# ABOUTME: Multi-character terminals skip intermediate positions which should not be treated as stalls.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Desugar;
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;

sub terminal($v) { Chalk::Grammar::Symbol->new(type => 'terminal', value => $v) }
sub reference($v) { Chalk::Grammar::Symbol->new(type => 'reference', value => $v) }

# Grammar: S ::= '(' E ')'
#          E ::= /[a-z]+/
# The terminal [a-z]+ scans multiple characters, skipping intermediate positions.
my @rules = (
    Chalk::Grammar::Rule->new(
        name        => 'S',
        expressions => [[terminal('\('), reference('E'), terminal('\)')]],
    ),
    Chalk::Grammar::Rule->new(
        name        => 'E',
        expressions => [[terminal('[a-z]+')]],
    ),
);

my $grammar = Chalk::Bootstrap::Desugar::desugar_grammar(\@rules);
my $bool = Chalk::Bootstrap::Semiring::Boolean->new();

# === Test 1: Valid input with multi-char terminal, recovery enabled ===
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar => $grammar, semiring => $bool, recover => true,
    );
    ok($parser->parse('(hello)'), 'multi-char terminal: valid input parses with recovery');
    is(scalar $parser->errors()->@*, 0, 'multi-char terminal: no false stall errors');
}

# === Test 2: Single-char terminals, recovery enabled (no skipped positions) ===
{
    my @rules2 = (
        Chalk::Grammar::Rule->new(
            name        => 'S',
            expressions => [[terminal('a'), terminal('b')]],
        ),
    );
    my $grammar2 = Chalk::Bootstrap::Desugar::desugar_grammar(\@rules2);
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar => $grammar2, semiring => $bool, recover => true,
    );
    ok($parser->parse('ab'), 'single-char terminals: valid input parses with recovery');
    is(scalar $parser->errors()->@*, 0, 'single-char terminals: no errors');
}

# === Test 3: Actual stall should still trigger recovery ===
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar => $grammar, semiring => $bool, recover => true,
    );
    # '(123)' should stall at position 1 because [a-z]+ doesn't match '1'
    my $result = $parser->parse('(123)');
    ok(!$result, 'actual stall: invalid input fails');
    ok($parser->errors()->@* > 0, 'actual stall: error recorded');
}

# === Test 4: Longer multi-char terminal ===
{
    my @rules3 = (
        Chalk::Grammar::Rule->new(
            name        => 'S',
            expressions => [[terminal('[a-zA-Z_]\w*')]],
        ),
    );
    my $grammar3 = Chalk::Bootstrap::Desugar::desugar_grammar(\@rules3);
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar => $grammar3, semiring => $bool, recover => true,
    );
    ok($parser->parse('hello_world_123'), 'long identifier: parses with recovery');
    is(scalar $parser->errors()->@*, 0, 'long identifier: no false stall errors');
}

done_testing();
