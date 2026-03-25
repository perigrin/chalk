# ABOUTME: Tests for core set discovery, DFA state tables, and GC lifetime (Component 5, #654).
# ABOUTME: Verifies core sets are registered, DFA tables built, and parse-lifetime GC works.
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

# Test 1: core_set_registry exists and is populated after parsing
{
    ok($parser->parse('a,b,c'), "parse succeeds");

    my $registry = $parser->core_set_registry();
    ok(defined $registry, "core_set_registry accessor exists");
    ok(ref($registry) eq 'HASH', "core_set_registry returns a hashref");

    my $count = scalar keys $registry->%*;
    ok($count > 0, "core_set_registry has entries ($count core sets)");
    # For "a,b,c" there are 6 positions (0..5), but some share core sets
    ok($count < 6, "fewer core sets than positions (reuse detected)");
}

# Test 2: DFA tables exist per core set
{
    my $dfa_tables = $parser->dfa_tables();
    ok(defined $dfa_tables, "dfa_tables accessor exists");
    ok(ref($dfa_tables) eq 'HASH', "dfa_tables returns a hashref");

    my $count = scalar keys $dfa_tables->%*;
    ok($count > 0, "dfa_tables has entries ($count states)");

    # Each DFA table should have terminal_map
    for my $cs_id (keys $dfa_tables->%*) {
        my $table = $dfa_tables->{$cs_id};
        ok(exists $table->{terminal_map}, "core set $cs_id has terminal_map");
        last;  # Just check one to keep test output manageable
    }
}

# Test 3: parse_state can be reset while preserving grammar-lifetime data
{
    my $registry_before = $parser->core_set_registry();
    my $count_before = scalar keys $registry_before->%*;
    my $dfa_before = $parser->dfa_tables();
    my $dfa_count_before = scalar keys $dfa_before->%*;

    $parser->reset_parse_state();

    my $registry_after = $parser->core_set_registry();
    my $dfa_after = $parser->dfa_tables();

    is(scalar keys $registry_after->%*, $count_before,
        "core_set_registry preserved after reset_parse_state");
    is(scalar keys $dfa_after->%*, $dfa_count_before,
        "dfa_tables preserved after reset_parse_state");
}

# Test 4: sequential parses produce correct results after reset
{
    $parser->reset_parse_state();
    ok($parser->parse('x,y'), "first parse after reset: accepts 'x,y'");

    $parser->reset_parse_state();
    ok($parser->parse('a,b,c,d'), "second parse after reset: accepts 'a,b,c,d'");

    $parser->reset_parse_state();
    ok(!$parser->parse('a,,b'), "third parse after reset: rejects 'a,,b'");
}

# Test 5: core set sharing — repetitive patterns share core sets
{
    $parser->reset_parse_state();
    # Clear registry to measure fresh
    my $old_registry = $parser->core_set_registry();
    $parser->_clear_grammar_caches();  # full reset for measurement

    ok($parser->parse('a,b,c,d,e,f,g,h'), "parse long list");

    my $registry = $parser->core_set_registry();
    my $core_set_count = scalar keys $registry->%*;
    # For "a,b,c,d,e,f,g,h" (15 positions), many positions share core sets
    # because the repeating pattern (Item, Comma, Item, ...) cycles
    ok($core_set_count < 15, "core set reuse: $core_set_count sets for 15 positions");
}

done_testing;
