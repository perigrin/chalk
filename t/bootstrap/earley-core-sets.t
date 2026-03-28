# ABOUTME: Tests that the DFA provides correct structural information for parsing.
# ABOUTME: Verifies DFA states, prediction, and parse correctness across resets.
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

# Test 1: DFA is built at construction time and has states
subtest 'DFA built at construction' => sub {
    my $dfa = $parser->lr0_dfa();
    ok(defined $dfa, "lr0_dfa accessor exists");
    my $states = $dfa->states();
    ok(scalar $states->@* > 0, "DFA has states");
    ok($dfa->state_count() > 0, "state_count is positive");
};

# Test 2: parse correctness preserved after reset_parse_state
subtest 'parse correctness across resets' => sub {
    ok($parser->parse('a,b,c'), "first parse: accepts 'a,b,c'");

    $parser->reset_parse_state();
    ok($parser->parse('x,y'), "after reset: accepts 'x,y'");

    $parser->reset_parse_state();
    ok($parser->parse('a,b,c,d'), "after second reset: accepts 'a,b,c,d'");

    $parser->reset_parse_state();
    ok(!$parser->parse('a,,b'), "after third reset: rejects 'a,,b'");
};

# Test 3: DFA state properties are consistent
subtest 'DFA state invariants' => sub {
    my $dfa = $parser->lr0_dfa();
    my $core_index = $parser->core_index();
    my $states = $dfa->states();

    for my $state ($states->@*) {
        # Every non-complete item with a terminal should be in terminal_map
        for my $core_id ($state->{core_ids}->@*) {
            next if $core_index->is_complete($core_id);
            my $sym = $core_index->symbol_after($core_id);
            next unless defined $sym;
            if ($sym->is_reference()) {
                ok(exists $state->{completion_map}{$sym->value()},
                    "state $state->{id}: completion_map has '${\$sym->value()}'");
            } else {
                ok(exists $state->{terminal_map}{$sym->value()},
                    "state $state->{id}: terminal_map has '${\$sym->value()}'");
            }
        }
    }
};

# Test 4: long list parses correctly (exercises DFA across many positions)
subtest 'long list parsing' => sub {
    $parser->reset_parse_state();
    ok($parser->parse('a,b,c,d,e,f,g,h'), "8-item list parses");

    $parser->reset_parse_state();
    my $long = join(',', ('x') x 100);
    ok($parser->parse($long), "100-item list parses");
};

done_testing;
