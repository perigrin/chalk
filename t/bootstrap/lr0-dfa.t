# ABOUTME: Tests for LR(0) DFA construction from grammar for Aycock prediction optimization.
# ABOUTME: Verifies DFA states, transitions, and nonkernel prediction lookups.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::CoreItemIndex;

# Load the DFA module
use_ok('Chalk::Bootstrap::LR0DFA');

# Helper to build a grammar and its core item index
my sub build_grammar_and_index(@rules) {
    my $index = Chalk::Bootstrap::CoreItemIndex->new();
    $index->build_from_grammar(\@rules);
    return (\@rules, $index);
}

# === Test 1: Simple sequential grammar ===
subtest 'DFA for S ::= A B, A ::= /a/, B ::= /b/' => sub {
    my $sym_A = Chalk::Grammar::Symbol->new(type => 'reference', value => 'A');
    my $sym_B = Chalk::Grammar::Symbol->new(type => 'reference', value => 'B');
    my $sym_a = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'a');
    my $sym_b = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'b');

    my $rule_S = Chalk::Grammar::Rule->new(
        name => 'S', expressions => [[$sym_A, $sym_B]],
    );
    my $rule_A = Chalk::Grammar::Rule->new(
        name => 'A', expressions => [[$sym_a]],
    );
    my $rule_B = Chalk::Grammar::Rule->new(
        name => 'B', expressions => [[$sym_b]],
    );

    my ($grammar, $index) = build_grammar_and_index($rule_S, $rule_A, $rule_B);

    my $dfa = Chalk::Bootstrap::LR0DFA->new(
        grammar    => $grammar,
        core_index => $index,
        rule_table => { S => $rule_S, A => $rule_A, B => $rule_B },
    );
    $dfa->build();

    ok($dfa->state_count() > 0, 'DFA has states');

    # Prediction for S should include S and A (first symbol is reference to A)
    my $s_items = $dfa->prediction_items_for('S');
    ok(defined $s_items, 'prediction_items_for S is defined');
    # S has 1 alt (dot=0) + A is transitively predicted (1 alt, dot=0) = 2 items
    is(scalar $s_items->@*, 2, 'S prediction includes S alt and transitive A');

    # Prediction for A should return just A's items
    my $a_items = $dfa->prediction_items_for('A');
    ok(defined $a_items, 'prediction_items_for A is defined');
    is(scalar $a_items->@*, 1, 'A has 1 prediction item');

    # Prediction for B should return just B's items
    my $b_items = $dfa->prediction_items_for('B');
    ok(defined $b_items, 'prediction_items_for B is defined');
    is(scalar $b_items->@*, 1, 'B has 1 prediction item');

    # Prediction for nonexistent rule returns undef
    my $z_items = $dfa->prediction_items_for('Z');
    ok(!defined $z_items, 'prediction_items_for unknown rule returns undef');
};

# === Test 2: Grammar with alternatives ===
subtest 'DFA for grammar with alternatives' => sub {
    my $sym_a = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'a');
    my $sym_b = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'b');

    my $rule_S = Chalk::Grammar::Rule->new(
        name => 'S', expressions => [[$sym_a], [$sym_b]],
    );

    my ($grammar, $index) = build_grammar_and_index($rule_S);
    my $dfa = Chalk::Bootstrap::LR0DFA->new(
        grammar    => $grammar,
        core_index => $index,
        rule_table => { S => $rule_S },
    );
    $dfa->build();

    # S with two alternatives should have prediction items for both
    my $s_items = $dfa->prediction_items_for('S');
    ok(defined $s_items, 'S has prediction items');
    is(scalar $s_items->@*, 2, 'S has 2 prediction items (one per alt)');
};

# === Test 3: Recursive grammar ===
subtest 'DFA handles recursive grammar' => sub {
    my $sym_S = Chalk::Grammar::Symbol->new(type => 'reference', value => 'S');
    my $sym_a = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'a');

    my $rule_S = Chalk::Grammar::Rule->new(
        name => 'S', expressions => [[$sym_a, $sym_S], [$sym_a]],
    );

    my ($grammar, $index) = build_grammar_and_index($rule_S);
    my $dfa = Chalk::Bootstrap::LR0DFA->new(
        grammar    => $grammar,
        core_index => $index,
        rule_table => { S => $rule_S },
    );
    $dfa->build();

    ok($dfa->state_count() > 0, 'DFA built for recursive grammar');
    my $s_items = $dfa->prediction_items_for('S');
    ok(defined $s_items, 'recursive S has prediction items');
    is(scalar $s_items->@*, 2, 'both alternatives present');
};

# === Test 4: Transitive prediction ===
subtest 'DFA transitive prediction' => sub {
    # S ::= A, A ::= B, B ::= /x/
    # Predicting S should transitively include A and B items
    my $sym_A = Chalk::Grammar::Symbol->new(type => 'reference', value => 'A');
    my $sym_B = Chalk::Grammar::Symbol->new(type => 'reference', value => 'B');
    my $sym_x = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'x');

    my $rule_S = Chalk::Grammar::Rule->new(name => 'S', expressions => [[$sym_A]]);
    my $rule_A = Chalk::Grammar::Rule->new(name => 'A', expressions => [[$sym_B]]);
    my $rule_B = Chalk::Grammar::Rule->new(name => 'B', expressions => [[$sym_x]]);

    my ($grammar, $index) = build_grammar_and_index($rule_S, $rule_A, $rule_B);
    my $dfa = Chalk::Bootstrap::LR0DFA->new(
        grammar    => $grammar,
        core_index => $index,
        rule_table => { S => $rule_S, A => $rule_A, B => $rule_B },
    );
    $dfa->build();

    my $s_items = $dfa->prediction_items_for('S');
    # S(dot=0) + A(dot=0) + B(dot=0) = 3 items
    is(scalar $s_items->@*, 3, 'S prediction transitively includes A and B');
};

# === Test 5: Integration with Earley parser ===
subtest 'DFA-enhanced Earley parser produces correct results' => sub {
    my $sym_A = Chalk::Grammar::Symbol->new(type => 'reference', value => 'A');
    my $sym_B = Chalk::Grammar::Symbol->new(type => 'reference', value => 'B');
    my $sym_a = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'a');
    my $sym_b = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'b');

    my $rule_S = Chalk::Grammar::Rule->new(
        name => 'S', expressions => [[$sym_A, $sym_B]],
    );
    my $rule_A = Chalk::Grammar::Rule->new(
        name => 'A', expressions => [[$sym_a]],
    );
    my $rule_B = Chalk::Grammar::Rule->new(
        name => 'B', expressions => [[$sym_b]],
    );

    my $grammar = [$rule_S, $rule_A, $rule_B];

    use Chalk::Bootstrap::Semiring::Boolean;
    use Chalk::Bootstrap::Earley;

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('ab'), 'DFA parser accepts "ab"');
    ok(!$parser->parse('ba'), 'DFA parser rejects "ba"');
    ok(!$parser->parse('aa'), 'DFA parser rejects "aa"');
    ok(!$parser->parse(''), 'DFA parser rejects empty');
};

# === Test 6: prediction_items_for returns correct core IDs ===
subtest 'prediction items have correct core IDs' => sub {
    my $sym_a = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'a');
    my $sym_b = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'b');
    my $sym_E = Chalk::Grammar::Symbol->new(type => 'reference', value => 'E');

    my $rule_E = Chalk::Grammar::Rule->new(
        name => 'E', expressions => [[$sym_a], [$sym_b], [$sym_E, $sym_a]],
    );

    my ($grammar, $index) = build_grammar_and_index($rule_E);
    my $dfa = Chalk::Bootstrap::LR0DFA->new(
        grammar    => $grammar,
        core_index => $index,
        rule_table => { E => $rule_E },
    );
    $dfa->build();

    my $items = $dfa->prediction_items_for('E');
    is(scalar $items->@*, 3, 'E has 3 prediction items');

    # Each prediction item should be at dot position 0
    for my $core_id ($items->@*) {
        my $info = $index->item_for($core_id);
        ok(defined $info, "core_id $core_id exists in index");
        is($info->{rule_name}, 'E', "core_id $core_id is for rule E");
        is($info->{dot}, 0, "core_id $core_id has dot at 0");
    }
};

done_testing;
