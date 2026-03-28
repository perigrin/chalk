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

# === Test 5: O(1) scalar accessors from register() ===
subtest 'rule_name_for, alt_idx_for, dot_for return correct values' => sub {
    my $index = Chalk::Bootstrap::CoreItemIndex->new();
    $index->register('Expr', 2, 3);
    $index->register('Stmt', 0, 0);

    my $id_expr = $index->id_for('Expr', 2, 3);
    is($index->rule_name_for($id_expr), 'Expr', 'rule_name_for returns rule name');
    is($index->alt_idx_for($id_expr),   2,      'alt_idx_for returns alt index');
    is($index->dot_for($id_expr),       3,      'dot_for returns dot position');

    my $id_stmt = $index->id_for('Stmt', 0, 0);
    is($index->rule_name_for($id_stmt), 'Stmt', 'rule_name_for correct for second item');
    is($index->alt_idx_for($id_stmt),   0,      'alt_idx_for correct for second item');
    is($index->dot_for($id_stmt),       0,      'dot_for correct for second item');

    ok(!defined $index->rule_for($id_expr), 'rule_for returns undef without build_from_grammar');
};

# === Test 6: rule_for returns Rule object from build_from_grammar() ===
subtest 'rule_for returns Rule object' => sub {
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

    my $id_s00 = $index->id_for('S', 0, 0);
    my $rule = $index->rule_for($id_s00);
    ok(defined $rule, 'rule_for returns defined Rule object');
    isa_ok($rule, 'Chalk::Grammar::Rule', 'rule_for returns a Rule');
    is($rule->name(), 'S', 'rule_for returns correct Rule by name');

    my $id_a00 = $index->id_for('A', 0, 0);
    my $rule_a = $index->rule_for($id_a00);
    is($rule_a->name(), 'A', 'rule_for returns correct Rule for A');

    # All dot positions for the same rule/alt share the same Rule object
    my $id_s01 = $index->id_for('S', 0, 1);
    is($index->rule_for($id_s01), $rule_S, 'rule_for same object for different dots of same rule');
};

# === Test 7: scalar accessors consistent with item_for ===
subtest 'scalar accessors are consistent with item_for' => sub {
    my $index = Chalk::Bootstrap::CoreItemIndex->new();
    $index->register('Block', 3, 7);

    my $id = $index->id_for('Block', 3, 7);
    my $info = $index->item_for($id);

    is($index->rule_name_for($id), $info->{rule_name}, 'rule_name_for matches item_for');
    is($index->alt_idx_for($id),   $info->{alt_idx},   'alt_idx_for matches item_for');
    is($index->dot_for($id),       $info->{dot},       'dot_for matches item_for');
};

# === Test 8: state_for_core mapping ===
subtest 'state_for_core mapping' => sub {
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

    # Before any state assignment, state_for returns undef
    my $id_s00 = $index->id_for('S', 0, 0);
    ok(!defined $index->state_for($id_s00), 'state_for returns undef before assignment');

    # Assign states
    $index->set_state_for($id_s00, 0);
    is($index->state_for($id_s00), 0, 'state_for returns assigned state');

    my $id_a00 = $index->id_for('A', 0, 0);
    $index->set_state_for($id_a00, 1);
    is($index->state_for($id_a00), 1, 'state_for returns different state for different item');

    # Bulk accessor returns arrayref for hot-loop direct indexing
    my $bulk = $index->states_for_bulk();
    ok(ref $bulk eq 'ARRAY', 'states_for_bulk returns arrayref');
    is($bulk->[$id_s00], 0, 'bulk accessor matches state_for for S');
    is($bulk->[$id_a00], 1, 'bulk accessor matches state_for for A');

    # Unassigned items are undef in the bulk array
    my $id_b00 = $index->id_for('B', 0, 0);
    ok(!defined $bulk->[$id_b00], 'unassigned items are undef in bulk array');
};

done_testing;
