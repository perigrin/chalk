# ABOUTME: Full LR(0) DFA construction from grammar with closure/goto algorithm.
# ABOUTME: Builds states with terminal maps, completion maps, goto tables, and state_for_core mapping.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::LR0DFA {
    field $grammar    :param :reader;  # arrayref of Rule objects
    field $core_index :param :reader;  # CoreItemIndex
    field $rule_table :param :reader;  # { rule_name => Rule }

    # Prediction cache: { nonterminal_name => [[$core_id, $skip_symbols], ...] }
    # Each entry is the set of core items reachable by transitively predicting
    # nonterminals. Includes dot>0 items for nullable symbol advancement.
    # $skip_symbols is an arrayref of ?-quantified symbol names skipped to reach
    # this dot position (empty arrayref for dot=0 items).
    field %prediction_items;

    # Nullable set: { nonterminal_name => true } for nonterminals that can
    # derive the empty string. Computed via fixed-point iteration.
    field %nullable;

    # Full DFA states: array indexed by state_id
    # Each state: { id, core_ids, terminal_map, completion_map, goto_table }
    field @states;

    # State registry: sorted core_ids key => state_id (deduplication)
    field %state_registry;

    # State count for reporting
    field $state_count :reader = 0;

    # Accessors for DFA states
    method states()         { return \@states }
    method state($id)       { return $states[$id] }
    method state_count_dfa(){ return scalar @states }

    # Build the DFA: nullable set, prediction closures, then full state construction.
    method build() {
        $self->_compute_nullable_set();

        # Prediction closures (used by predict() at parse time)
        for my $rule ($grammar->@*) {
            my $name = $rule->name();
            next if exists $prediction_items{$name};
            $self->_compute_prediction_closure($name);
        }

        # Full DFA state construction via closure/goto
        $self->_build_dfa_states();

        $state_count = scalar @states;
    }

    # Compute LR(0) closure of a kernel set of core_ids.
    # Returns a sorted arrayref of all core_ids reachable by transitively
    # following nonterminal references (predictions) and advancing past
    # nullable symbols (Aycock-Horspool optimization).
    method _closure($kernel) {
        my %in_set;
        $in_set{$_} = 1 for $kernel->@*;
        my @worklist = $kernel->@*;

        while (@worklist) {
            my $core_id = shift @worklist;
            next if $core_index->is_complete($core_id);
            my $sym = $core_index->symbol_after($core_id);
            next unless defined $sym && $sym->is_reference();

            my $nt = $sym->value();
            my $rule = $rule_table->{$nt};
            next unless defined $rule;

            # Add prediction items for all alternatives of this nonterminal
            my $expressions = $rule->expressions();
            for my $alt_idx (0 .. $expressions->$#*) {
                my $pred_id = $core_index->id_for($nt, $alt_idx, 0);
                if (defined $pred_id && !$in_set{$pred_id}) {
                    $in_set{$pred_id} = 1;
                    push @worklist, $pred_id;
                }
            }

            # Aycock-Horspool: if the nonterminal is nullable or ?-quantified,
            # advance past it and add the advanced item to the closure
            my $is_nullable_sym = ($sym->is_quantified() && $sym->quantifier() eq '?')
                               || $nullable{$nt};
            if ($is_nullable_sym) {
                my $adv_id = $core_index->advance($core_id);
                if (defined $adv_id && !$in_set{$adv_id}) {
                    $in_set{$adv_id} = 1;
                    push @worklist, $adv_id;
                }
            }
        }

        return [sort { $a <=> $b } keys %in_set];
    }

    # Compute goto(state, symbol): the set of core_ids reachable by advancing
    # all items in the state that have the given symbol after their dot.
    # Returns closure of the advanced kernel, or undef if no items match.
    method _goto($state_core_ids, $symbol_str, $symbol_is_ref) {
        my @kernel;
        for my $core_id ($state_core_ids->@*) {
            next if $core_index->is_complete($core_id);
            my $sym = $core_index->symbol_after($core_id);
            next unless defined $sym;

            # Match by symbol string (value for both terminals and references)
            my $this_str = $sym->value();
            my $this_is_ref = $sym->is_reference();
            next unless $this_str eq $symbol_str && $this_is_ref == $symbol_is_ref;

            my $adv = $core_index->advance($core_id);
            push @kernel, $adv if defined $adv;
        }
        return undef unless @kernel;
        return $self->_closure(\@kernel);
    }

    # Build the full DFA via subset construction.
    method _build_dfa_states() {
        @states = ();
        %state_registry = ();

        # Start state: closure of start rule's alternatives at dot=0
        my $start_rule = $grammar->[0];
        my @start_kernel;
        my $expressions = $start_rule->expressions();
        for my $alt_idx (0 .. $expressions->$#*) {
            my $id = $core_index->id_for($start_rule->name(), $alt_idx, 0);
            push @start_kernel, $id if defined $id;
        }
        my $start_core_ids = $self->_closure(\@start_kernel);
        $self->_register_state($start_core_ids);

        # Iterate states, computing goto for each symbol
        my $i = 0;
        while ($i < scalar @states) {
            my $state = $states[$i];
            my $core_ids = $state->{core_ids};

            # Collect all distinct symbols after the dot in this state
            my %symbols;  # symbol_str => is_reference
            for my $core_id ($core_ids->@*) {
                next if $core_index->is_complete($core_id);
                my $sym = $core_index->symbol_after($core_id);
                next unless defined $sym;
                $symbols{$sym->value()} = $sym->is_reference();
            }

            # Compute goto for each symbol
            for my $sym_str (sort keys %symbols) {
                my $is_ref = $symbols{$sym_str};
                my $target_core_ids = $self->_goto($core_ids, $sym_str, $is_ref);
                next unless defined $target_core_ids;

                my $target_id = $self->_register_state($target_core_ids);
                $state->{goto_table}{$sym_str} = $target_id;
            }

            $i++;
        }

        # Populate state_for_core mapping in CoreItemIndex
        for my $state (@states) {
            for my $core_id ($state->{core_ids}->@*) {
                $core_index->set_state_for($core_id, $state->{id});
            }
        }
    }

    # Register a new state or return existing state ID if already known.
    # Also builds terminal_map and completion_map for new states.
    method _register_state($core_ids) {
        my $key = join(',', $core_ids->@*);
        return $state_registry{$key} if exists $state_registry{$key};

        my $state_id = scalar @states;
        $state_registry{$key} = $state_id;

        # Build terminal map and completion map
        my %terminal_map;
        my %completion_map;
        for my $core_id ($core_ids->@*) {
            next if $core_index->is_complete($core_id);
            my $sym = $core_index->symbol_after($core_id);
            next unless defined $sym;
            if ($sym->is_reference()) {
                my $nt = $sym->value();
                $completion_map{$nt} //= [];
                push $completion_map{$nt}->@*, $core_id;
            } else {
                my $pattern = $sym->value();
                $terminal_map{$pattern} //= [];
                push $terminal_map{$pattern}->@*, $core_id;
            }
        }

        push @states, {
            id             => $state_id,
            core_ids       => $core_ids,
            terminal_map   => \%terminal_map,
            completion_map => \%completion_map,
            goto_table     => {},
        };

        return $state_id;
    }

    # Compute the set of nullable nonterminals using fixed-point iteration.
    # A nonterminal N is nullable if any of its alternatives:
    #   - Is empty (epsilon production), OR
    #   - Has all symbols being nullable (nonterminal + nullable, or ?-quantified)
    method _compute_nullable_set() {
        # Seed: find all nonterminals with empty alternatives
        my $changed = true;
        for my $rule ($grammar->@*) {
            for my $alt ($rule->expressions()->@*) {
                if (scalar $alt->@* == 0) {
                    $nullable{$rule->name()} = true;
                }
            }
        }

        # Fixed-point: iterate until no new nullables found
        while ($changed) {
            $changed = false;
            for my $rule ($grammar->@*) {
                my $name = $rule->name();
                next if $nullable{$name};
                for my $alt ($rule->expressions()->@*) {
                    my $all_nullable = true;
                    for my $sym ($alt->@*) {
                        if ($sym->is_quantified() && $sym->quantifier() eq '?') {
                            # ?-quantified symbols are inherently nullable
                            next;
                        }
                        if ($sym->is_reference() && $nullable{$sym->value()}) {
                            # Nullable nonterminal reference
                            next;
                        }
                        # Non-nullable symbol found
                        $all_nullable = false;
                        last;
                    }
                    if ($all_nullable && scalar $alt->@* > 0) {
                        $nullable{$name} = true;
                        $changed = true;
                    }
                }
            }
        }
    }

    # Check if a nonterminal is nullable.
    method is_nullable($nonterminal) {
        return $nullable{$nonterminal} ? true : false;
    }

    # Compute the epsilon-closure for a nonterminal: all core items
    # reachable by transitively following nonterminal references.
    # Includes dot-advanced items past nullable symbols (Aycock optimization).
    method _compute_prediction_closure($nonterminal) {
        my @result;
        my %visited;  # nonterminals already expanded
        my @worklist = ($nonterminal);

        while (my $nt = shift @worklist) {
            next if $visited{$nt}++;
            my $rule = $rule_table->{$nt};
            next unless defined $rule;

            my $expressions = $rule->expressions();
            for my $alt_idx (0 .. $expressions->$#*) {
                # Add core item at dot=0 for this alternative
                my $core_id = $core_index->id_for($nt, $alt_idx, 0);
                push @result, [$core_id, []] if defined $core_id;

                # Advance through consecutive nullable symbols at the start
                # of this alternative, adding dot-advanced items.
                my $alt = $expressions->[$alt_idx];
                my $dot = 0;
                my @skipped;  # Track ?-quantified symbol names skipped
                while ($dot < scalar $alt->@*) {
                    my $sym = $alt->[$dot];
                    last unless $sym->is_reference();
                    my $ref_name = $sym->value();
                    push @worklist, $ref_name unless $visited{$ref_name};

                    # Is this symbol nullable (can be skipped)?
                    my $is_nullable_sym = ($sym->is_quantified() && $sym->quantifier() eq '?')
                                       || $nullable{$ref_name};
                    if ($is_nullable_sym) {
                        # Track ?-quantified skips for on_skip_optional placeholders
                        my @skip_copy = @skipped;
                        if ($sym->is_quantified() && $sym->quantifier() eq '?') {
                            push @skip_copy, $ref_name;
                        }
                        # Add dot-advanced core item
                        my $adv_id = $core_index->id_for($nt, $alt_idx, $dot + 1);
                        push @result, [$adv_id, \@skip_copy] if defined $adv_id;
                        # Update running skip list for further advancement
                        if ($sym->is_quantified() && $sym->quantifier() eq '?') {
                            push @skipped, $ref_name;
                        }
                        $dot++;
                    } else {
                        last;
                    }
                }
            }
        }

        $prediction_items{$nonterminal} = \@result;
    }

    # Get the prediction items for a nonterminal: core items
    # reachable via epsilon-closure, including dot-advanced items.
    # Returns arrayref of [$core_id, $skip_symbols] pairs.
    method prediction_items_for($nonterminal) {
        return $prediction_items{$nonterminal};
    }
}
