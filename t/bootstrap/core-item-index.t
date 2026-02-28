# ABOUTME: Tests for CoreItemIndex which enumerates (rule_name, alt_idx, dot) triples as integer IDs.
# ABOUTME: Verifies registration, lookup, advance, and build_from_grammar operations.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;

# Load the module under test
use_ok('Chalk::Bootstrap::CoreItemIndex');

# === Test 1: Basic registration and lookup ===
subtest 'register and id_for round-trip' => sub {
    my $index = Chalk::Bootstrap::CoreItemIndex->new();
    my $id = $index->register('S', 0, 0);
    is($id, 0, 'first registered item gets ID 0');

    my $id2 = $index->register('S', 0, 1);
    is($id2, 1, 'second registered item gets ID 1');

    # Same triple returns same ID
    my $id_dup = $index->register('S', 0, 0);
    is($id_dup, 0, 'duplicate registration returns same ID');

    # Lookup by triple
    is($index->id_for('S', 0, 0), 0, 'id_for returns correct ID');
    is($index->id_for('S', 0, 1), 1, 'id_for returns correct ID for second item');
    ok(!defined $index->id_for('Z', 0, 0), 'id_for returns undef for unknown triple');

    is($index->count(), 2, 'count reflects registered items');
};

# === Test 2: item_for reverse lookup ===
subtest 'item_for returns correct info' => sub {
    my $index = Chalk::Bootstrap::CoreItemIndex->new();
    $index->register('A', 1, 2);

    my $info = $index->item_for(0);
    ok(defined $info, 'item_for returns defined value');
    is($info->{rule_name}, 'A', 'correct rule_name');
    is($info->{alt_idx}, 1, 'correct alt_idx');
    is($info->{dot}, 2, 'correct dot');
};

# === Test 3: advance returns dot+1 ID ===
subtest 'advance returns next dot position' => sub {
    my $index = Chalk::Bootstrap::CoreItemIndex->new();
    $index->register('S', 0, 0);
    $index->register('S', 0, 1);
    $index->register('S', 0, 2);

    is($index->advance(0), 1, 'advance(0) returns ID for dot=1');
    is($index->advance(1), 2, 'advance(1) returns ID for dot=2');
    ok(!defined $index->advance(2), 'advance(2) returns undef (no dot=3 registered)');
};

# === Test 4: build_from_grammar ===
subtest 'build_from_grammar enumerates all core items' => sub {
    my $sym_a = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'a');
    my $sym_b = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'b');
    my $sym_A = Chalk::Grammar::Symbol->new(type => 'reference', value => 'A');
    my $sym_B = Chalk::Grammar::Symbol->new(type => 'reference', value => 'B');

    my $rule_S = Chalk::Grammar::Rule->new(
        name => 'S', expressions => [[$sym_A, $sym_B], [$sym_a]],
    );
    my $rule_A = Chalk::Grammar::Rule->new(
        name => 'A', expressions => [[$sym_a]],
    );
    my $rule_B = Chalk::Grammar::Rule->new(
        name => 'B', expressions => [[$sym_b]],
    );

    my $index = Chalk::Bootstrap::CoreItemIndex->new();
    $index->build_from_grammar([$rule_S, $rule_A, $rule_B]);

    # S alt 0: [A, B] -> dot positions 0, 1, 2 = 3 items
    # S alt 1: [a]    -> dot positions 0, 1 = 2 items
    # A alt 0: [a]    -> dot positions 0, 1 = 2 items
    # B alt 0: [b]    -> dot positions 0, 1 = 2 items
    # Total: 9
    is($index->count(), 9, 'correct total core item count');

    # Verify specific items exist
    ok(defined $index->id_for('S', 0, 0), 'S alt 0 dot 0 exists');
    ok(defined $index->id_for('S', 0, 2), 'S alt 0 dot 2 exists');
    ok(defined $index->id_for('S', 1, 0), 'S alt 1 dot 0 exists');
    ok(defined $index->id_for('S', 1, 1), 'S alt 1 dot 1 exists');
    ok(defined $index->id_for('A', 0, 0), 'A alt 0 dot 0 exists');
    ok(defined $index->id_for('B', 0, 1), 'B alt 0 dot 1 exists');

    # Advance should work for items from build
    my $s0_0 = $index->id_for('S', 0, 0);
    my $s0_1 = $index->id_for('S', 0, 1);
    is($index->advance($s0_0), $s0_1, 'advance works for grammar-built items');
};

done_testing;
