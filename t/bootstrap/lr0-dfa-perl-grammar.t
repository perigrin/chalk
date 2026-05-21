# ABOUTME: Integration test for LR0DFA with the real 63-rule Perl grammar.
# ABOUTME: Verifies DFA construction, state count, and invariants on a production-scale grammar.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Desugar;
use Chalk::Bootstrap::CoreItemIndex;
use Chalk::Bootstrap::LR0DFA;

# Build the Perl grammar through the BNF pipeline
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse from BNF', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::DFAInteg/g;
    eval $generated;
    skip "Generated Perl grammar code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::DFAInteg::grammar();
    skip 'Generated grammar returned undef', 1 unless defined $gen_grammar;

    # Reorder so Program is the start rule (grammar->[0] convention)
    my @reordered;
    my $found = false;
    for my $rule ($gen_grammar->@*) {
        if (!$found && $rule->name() eq 'Program') {
            unshift @reordered, $rule;
            $found = true;
        } else {
            push @reordered, $rule;
        }
    }
    skip 'Program rule not found in grammar', 1 unless $found;

    # Desugar (expands * and + quantifiers into helper rules)
    my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar(\@reordered);

    # Build CoreItemIndex and LR0DFA
    my $core_index = Chalk::Bootstrap::CoreItemIndex->new();
    $core_index->build_from_grammar($desugared);

    my %rule_table = map { $_->name() => $_ } $desugared->@*;

    my $dfa = Chalk::Bootstrap::LR0DFA->new(
        grammar    => $desugared,
        core_index => $core_index,
        rule_table => \%rule_table,
    );
    $dfa->build();

    my $states = $dfa->states();
    my $num_states = scalar $states->@*;
    my $num_rules = scalar $desugared->@*;
    my $num_core_items = $core_index->count();

    diag("Perl grammar: $num_rules rules, $num_core_items core items, $num_states DFA states");

    # Sanity checks
    subtest 'DFA produces reasonable number of states' => sub {
        ok($num_states > 0, 'at least one state');
        ok($num_states >= $num_rules, "states ($num_states) >= rules ($num_rules)");
        # Design doc Section 5.5 says ~80-120 states for 65-rule grammar
        # After desugaring we have more rules, so allow broader range
        ok($num_states < 1000, "states ($num_states) < 1000 (sanity bound)");
    };

    # Invariant 3: terminal map covers all terminal-expecting items
    subtest 'Perl grammar: terminal map coverage' => sub {
        my $checked = 0;
        for my $state ($states->@*) {
            for my $core_id ($state->{core_ids}->@*) {
                next if $core_index->is_complete($core_id);
                my $sym = $core_index->symbol_after($core_id);
                next unless defined $sym;
                next if $sym->is_reference();
                my $pattern = $sym->value();
                ok(exists $state->{terminal_map}{$pattern},
                    "state $state->{id}: terminal in terminal_map")
                    or diag("missing terminal '$pattern' in state $state->{id}");
                $checked++;
            }
        }
        ok($checked > 0, "checked $checked terminal-expecting items");
    };

    # Invariant 4: completion map covers all nonterminal-waiting items
    subtest 'Perl grammar: completion map coverage' => sub {
        my $checked = 0;
        for my $state ($states->@*) {
            for my $core_id ($state->{core_ids}->@*) {
                next if $core_index->is_complete($core_id);
                my $sym = $core_index->symbol_after($core_id);
                next unless defined $sym;
                next unless $sym->is_reference();
                my $nt = $sym->value();
                ok(exists $state->{completion_map}{$nt},
                    "state $state->{id}: nonterminal in completion_map")
                    or diag("missing nonterminal '$nt' in state $state->{id}");
                $checked++;
            }
        }
        ok($checked > 0, "checked $checked nonterminal-waiting items");
    };

    # Invariant 5: goto transitions are consistent
    subtest 'Perl grammar: goto transition consistency' => sub {
        my $checked = 0;
        for my $state ($states->@*) {
            for my $sym_key (keys $state->{goto_table}->%*) {
                my $target_id = $state->{goto_table}{$sym_key};
                my $target = $dfa->state($target_id);
                ok(defined $target,
                    "state $state->{id}: goto target $target_id exists")
                    or next;

                # Verify advanced items are in target
                my %in_target = map { $_ => 1 } $target->{core_ids}->@*;
                for my $core_id ($state->{core_ids}->@*) {
                    next if $core_index->is_complete($core_id);
                    my $sym = $core_index->symbol_after($core_id);
                    next unless defined $sym;
                    next unless $sym->goto_key() eq $sym_key;

                    my $advanced = $core_index->advance($core_id);
                    next unless defined $advanced;
                    ok($in_target{$advanced},
                        "state $state->{id}: advance($core_id) in goto target $target_id")
                        or diag("advanced core_id $advanced not in target state $target_id");
                    $checked++;
                }
            }
        }
        ok($checked > 0, "checked $checked goto transitions");
    };

    # Invariant 2: nonkernel = prediction closure of kernel
    subtest 'Perl grammar: nonkernel = closure(kernel) - kernel' => sub {
        my $start_rule_name = $desugared->[0]->name();
        my $failures = 0;
        for my $state ($states->@*) {
            my @kernel;
            my @nonkernel;
            for my $core_id ($state->{core_ids}->@*) {
                my $dot = $core_index->dot_for($core_id);
                if ($dot > 0) {
                    push @kernel, $core_id;
                } elsif ($state->{id} == 0
                         && $core_index->rule_name_for($core_id) eq $start_rule_name) {
                    push @kernel, $core_id;
                } else {
                    push @nonkernel, $core_id;
                }
            }

            my $closure = $dfa->_closure(\@kernel);
            my %kernel_set = map { $_ => 1 } @kernel;
            my @expected = sort { $a <=> $b }
                grep { !$kernel_set{$_} } $closure->@*;
            my @actual = sort { $a <=> $b } @nonkernel;

            if (!is_deeply(\@actual, \@expected,
                    "state $state->{id}: nonkernel matches closure")) {
                $failures++;
                last if $failures >= 3;  # Don't flood output
            }
        }
    };

    # state_for_core: every core_id maps to a valid containing state
    subtest 'Perl grammar: state_for_core validity' => sub {
        my %valid_states;
        for my $state ($states->@*) {
            for my $core_id ($state->{core_ids}->@*) {
                $valid_states{$core_id} //= [];
                push $valid_states{$core_id}->@*, $state->{id};
            }
        }

        my $checked = 0;
        my $multi_state = 0;
        for my $core_id (sort { $a <=> $b } keys %valid_states) {
            my $mapped = $core_index->state_for($core_id);
            ok(defined $mapped, "core_id $core_id has state_for mapping")
                or next;
            my %valid = map { $_ => 1 } $valid_states{$core_id}->@*;
            ok($valid{$mapped},
                "core_id $core_id maps to valid state $mapped")
                or diag("valid states: " . join(', ', sort keys %valid));
            $checked++;
            $multi_state++ if scalar(keys %valid) > 1;
        }
        ok($checked > 0, "checked $checked core_id state mappings");
        diag("$multi_state core_ids appear in multiple states (nonkernel sharing)");
    };
}

done_testing;
