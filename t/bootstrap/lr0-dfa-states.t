# ABOUTME: Tests for full LR(0) DFA state construction with closure/goto.
# ABOUTME: Verifies state registry, terminal maps, completion maps, goto tables, and invariants.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::CoreItemIndex;
use Chalk::Bootstrap::LR0DFA;

sub terminal { Chalk::Grammar::Symbol->new(type => 'terminal', value => $_[0]) }
sub reference { Chalk::Grammar::Symbol->new(type => 'reference', value => $_[0]) }

# ====================================================================
# Arithmetic grammar (matches Section 5.4 of the design doc)
# ====================================================================
# Expr   ::= Expr '+' Term    (alt 0)
#           | Term             (alt 1)
# Term   ::= 'number'         (alt 0)
my @grammar = (
    Chalk::Grammar::Rule->new(name => 'Expr', expressions => [
        [reference('Expr'), terminal('\+'), reference('Term')],
        [reference('Term')],
    ]),
    Chalk::Grammar::Rule->new(name => 'Term', expressions => [
        [terminal('\d+')],
    ]),
);

my %rule_table = map { $_->name() => $_ } @grammar;

my $core_index = Chalk::Bootstrap::CoreItemIndex->new();
$core_index->build_from_grammar(\@grammar);

my $dfa = Chalk::Bootstrap::LR0DFA->new(
    grammar    => \@grammar,
    core_index => $core_index,
    rule_table => \%rule_table,
);
$dfa->build();

# === Test 1: DFA produces states ===
subtest 'DFA construction produces states' => sub {
    my $states = $dfa->states();
    ok(defined $states, 'states() returns defined value');
    ok(ref $states eq 'ARRAY', 'states() returns arrayref');
    ok(scalar $states->@* > 0, 'at least one state exists');

    # Section 5.4 says the arithmetic grammar produces 6 states
    is(scalar $states->@*, 6, 'arithmetic grammar produces 6 DFA states');
};

# === Test 2: Start state contains correct kernel ===
subtest 'start state contents' => sub {
    my $start = $dfa->state(0);
    ok(defined $start, 'state 0 exists');

    my $core_ids = $start->{core_ids};
    ok(defined $core_ids, 'state has core_ids');
    ok(scalar $core_ids->@* > 0, 'state has items');

    # Start state should contain Expr -> . Expr '+' Term (alt 0, dot 0)
    # and Expr -> . Term (alt 1, dot 0) plus predictions: Term -> . 'number'
    my $expr_0_0 = $core_index->id_for('Expr', 0, 0);
    my $expr_1_0 = $core_index->id_for('Expr', 1, 0);
    my $term_0_0 = $core_index->id_for('Term', 0, 0);

    my %in_state = map { $_ => 1 } $core_ids->@*;
    ok($in_state{$expr_0_0}, 'start state contains Expr -> . Expr "+" Term');
    ok($in_state{$expr_1_0}, 'start state contains Expr -> . Term');
    ok($in_state{$term_0_0}, 'start state contains Term -> . number (prediction)');
};

# === Test 3: Terminal maps ===
subtest 'terminal maps per state' => sub {
    my $start = $dfa->state(0);
    my $tmap = $start->{terminal_map};
    ok(defined $tmap, 'start state has terminal_map');
    ok(ref $tmap eq 'HASH', 'terminal_map is a hashref');

    # Start state should expect 'number' terminal (from Term -> . 'number')
    ok(exists $tmap->{'\\d+'}, 'start state terminal_map has number pattern');
    # Start state should NOT expect '+' (Expr -> . Expr '+' Term — dot before nonterminal Expr)
    ok(!exists $tmap->{'\\+'}, 'start state does not expect "+" (dot before nonterminal)');
};

# === Test 4: Completion maps ===
subtest 'completion maps per state' => sub {
    my $start = $dfa->state(0);
    my $cmap = $start->{completion_map};
    ok(defined $cmap, 'start state has completion_map');
    ok(ref $cmap eq 'HASH', 'completion_map is a hashref');

    # Start state items waiting for nonterminals:
    # Expr -> . Expr '+' Term waits for Expr
    # Expr -> . Term waits for Term
    ok(exists $cmap->{'Expr'}, 'start state completion_map has Expr');
    ok(exists $cmap->{'Term'}, 'start state completion_map has Term');
};

# === Test 5: Goto table ===
subtest 'goto table transitions' => sub {
    my $start = $dfa->state(0);
    my $goto = $start->{goto_table};
    ok(defined $goto, 'start state has goto_table');
    ok(ref $goto eq 'HASH', 'goto_table is a hashref');

    # Scanning 'number' from start state should transition somewhere
    # goto_table keys are prefixed: "t:" for terminals, "n:" for nonterminals
    ok(exists $goto->{'t:\\d+'}, 'goto_table has transition for number terminal');
    # Advancing past Expr should transition somewhere
    ok(exists $goto->{'n:Expr'}, 'goto_table has transition for Expr nonterminal');
    ok(exists $goto->{'n:Term'}, 'goto_table has transition for Term nonterminal');

    # The target states should be valid state IDs
    my $states = $dfa->states();
    my $max_id = $states->$#*;
    for my $sym (keys $goto->%*) {
        my $target = $goto->{$sym};
        ok($target >= 0 && $target <= $max_id,
            "goto target for '$sym' is valid state ID ($target)");
    }
};

# === Test 6: state_for_core mapping ===
subtest 'state_for_core maps to a valid containing state' => sub {
    my $states = $dfa->states();

    # Build the set of states that contain each core_id
    my %valid_states;
    for my $state ($states->@*) {
        for my $core_id ($state->{core_ids}->@*) {
            $valid_states{$core_id} //= [];
            push $valid_states{$core_id}->@*, $state->{id};
        }
    }

    # state_for must point to one of the valid states for each core_id
    for my $core_id (sort { $a <=> $b } keys %valid_states) {
        my $mapped = $core_index->state_for($core_id);
        ok(defined $mapped, "core_id $core_id has a state_for mapping");
        my %valid = map { $_ => 1 } $valid_states{$core_id}->@*;
        ok($valid{$mapped},
            "core_id $core_id maps to state $mapped (valid: " .
            join(', ', sort keys %valid) . ")");
    }
};

# === Test 7: DFA invariant assertions (Section 5.6) ===
subtest 'DFA invariant: terminal map covers all terminal-expecting items' => sub {
    my $states = $dfa->states();
    for my $state ($states->@*) {
        for my $core_id ($state->{core_ids}->@*) {
            next if $core_index->is_complete($core_id);
            my $sym = $core_index->symbol_after($core_id);
            next unless defined $sym;
            next if $sym->is_reference();
            my $pattern = $sym->value();
            ok(exists $state->{terminal_map}{$pattern},
                "state $state->{id}: terminal '$pattern' in terminal_map");
            my %in_tmap = map { $_ => 1 } $state->{terminal_map}{$pattern}->@*;
            ok($in_tmap{$core_id},
                "state $state->{id}: core_id $core_id in terminal_map for '$pattern'");
        }
    }
};

subtest 'DFA invariant: completion map covers all nonterminal-waiting items' => sub {
    my $states = $dfa->states();
    for my $state ($states->@*) {
        for my $core_id ($state->{core_ids}->@*) {
            next if $core_index->is_complete($core_id);
            my $sym = $core_index->symbol_after($core_id);
            next unless defined $sym;
            next unless $sym->is_reference();
            my $nt = $sym->value();
            ok(exists $state->{completion_map}{$nt},
                "state $state->{id}: nonterminal '$nt' in completion_map");
            my %in_cmap = map { $_ => 1 } $state->{completion_map}{$nt}->@*;
            ok($in_cmap{$core_id},
                "state $state->{id}: core_id $core_id in completion_map for '$nt'");
        }
    }
};

subtest 'DFA invariant: goto transitions are consistent' => sub {
    my $states = $dfa->states();
    for my $state ($states->@*) {
        for my $sym_str (keys $state->{goto_table}->%*) {
            my $target_id = $state->{goto_table}{$sym_str};
            my $target = $dfa->state($target_id);
            ok(defined $target, "state $state->{id}: goto target $target_id exists");

            # Every core_id in this state that has $sym_str after its dot,
            # when advanced, should appear in the target state.
            # goto_table keys are prefixed "t:" or "n:" — match the same way.
            for my $core_id ($state->{core_ids}->@*) {
                next if $core_index->is_complete($core_id);
                my $sym = $core_index->symbol_after($core_id);
                next unless defined $sym;
                my $sym_key = ($sym->is_reference() ? 'n:' : 't:') . $sym->value();
                next unless $sym_key eq $sym_str;

                my $advanced = $core_index->advance($core_id);
                next unless defined $advanced;

                my %in_target = map { $_ => 1 } $target->{core_ids}->@*;
                ok($in_target{$advanced},
                    "state $state->{id}: advance($core_id) = $advanced is in goto target $target_id");
            }
        }
    }
};

done_testing;
