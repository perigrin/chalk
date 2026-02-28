# ABOUTME: Scanless Earley parser with Predict/Scan/Complete operations.
# ABOUTME: Takes grammar and semiring, returns boolean acceptance for input strings.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Terminal;
use Chalk::Bootstrap::CoreItemIndex;
use Chalk::Bootstrap::LR0DFA;

class Chalk::Bootstrap::Earley {
    field $grammar  :param :reader;
    field $semiring :param :reader;

    # Build a lookup table for rules by name
    field $rule_table;

    # Core item index: maps (rule_name, alt_idx, dot) to small integer IDs
    field $core_index;

    # LR(0) DFA for prediction clustering
    field $lr0_dfa;

    # Secondary indexes for O(1) lookup during complete/advance
    # Reset at the start of each parse.
    # waiting_for: {rule_name}{pos} = [[core_id, origin], ...] — items waiting for a nonterminal
    # completed_at: {rule_name}{origin_pos}{chart_pos} = [[core_id, origin], ...] — completed items
    field %waiting_for;
    field %completed_at;

    # Compiled regex cache: pattern_string => qr// object
    field %regex_cache;

    # GC statistics for the most recent parse
    field %_gc_stats;

    # Per-position minimum origin for safe GC decisions
    field @_gc_min_origin_at;

    # Current position being processed (for GC tracking in _chart_set)
    field $_gc_current_pos;

    # Minimum origin across items at positions > $_gc_current_pos
    # Updated by _chart_set when items are placed at future positions
    field $_gc_future_min;

    ADJUST {
        $rule_table = {};
        for my $rule ($grammar->@*) {
            $rule_table->{$rule->name()} = $rule;
        }

        # Build core item index from grammar
        $core_index = Chalk::Bootstrap::CoreItemIndex->new();
        $core_index->build_from_grammar($grammar);

        # Build LR(0) DFA for prediction clustering
        $lr0_dfa = Chalk::Bootstrap::LR0DFA->new(
            grammar    => $grammar,
            core_index => $core_index,
            rule_table => $rule_table,
        );
        $lr0_dfa->build();
    }

    # GC statistics accessor
    method gc_stats() {
        return \%_gc_stats;
    }

    # Chart access helpers. Chart structure: $chart[$pos]{$core_id}{$origin} = [$item, $alt_idx]
    method _chart_has($chart, $pos, $core_id, $origin) {
        return exists $chart->[$pos]{$core_id} && exists $chart->[$pos]{$core_id}{$origin};
    }

    method _chart_get($chart, $pos, $core_id, $origin) {
        return $chart->[$pos]{$core_id}{$origin};
    }

    method _chart_set($chart, $pos, $core_id, $origin, $entry) {
        $chart->[$pos]{$core_id}{$origin} = $entry;
        # Track minimum origin per position for GC
        $_gc_min_origin_at[$pos] = $origin
            if !defined $_gc_min_origin_at[$pos] || $origin < $_gc_min_origin_at[$pos];
        # Track minimum origin across future positions (items placed by scan)
        if (defined $_gc_current_pos && $pos > $_gc_current_pos) {
            $_gc_future_min = $origin
                if !defined $_gc_future_min || $origin < $_gc_future_min;
        }
    }

    # Earley item: {rule, alt_idx, core_id, dot, origin, value}
    # We use hashrefs for items to make debugging easier
    method _make_item($rule, $alt_idx, $dot, $origin, $value) {
        my $core_id = $core_index->id_for($rule->name(), $alt_idx, $dot);
        return {
            rule    => $rule,
            alt_idx => $alt_idx,
            core_id => $core_id,
            dot     => $dot,
            origin  => $origin,
            value   => $value,
        };
    }

    # Get the symbol after the dot in an item
    method _symbol_after_dot($item, $alt_index) {
        my $rule = $item->{rule};
        my $dot = $item->{dot};
        my $alt = $rule->expressions()->[$alt_index];

        return undef if $dot >= scalar $alt->@*;
        return $alt->[$dot];
    }

    # Check if item is complete (dot at end)
    method _is_complete($item, $alt_index) {
        my $rule = $item->{rule};
        my $dot = $item->{dot};
        my $alt = $rule->expressions()->[$alt_index];

        return $dot >= scalar $alt->@*;
    }

    # Internal parse implementation that returns raw semiring value or undef
    method _run_parse($input) {
        my $n = length($input);

        # Chart: array of hashes, where each hash is {core_id}{origin} => [$item, $alt_idx]
        my @chart = map { {} } (0 .. $n);

        # Reset secondary indexes for this parse
        %waiting_for = ();
        %completed_at = ();
        %_gc_stats = (positions_freed => 0);
        @_gc_min_origin_at = ();
        $_gc_current_pos = undef;
        $_gc_future_min = undef;

        # Find the start rule (first rule in grammar)
        my $start_rule = $grammar->[0];

        # Initialize chart[0] with start rule items (one per alternative)
        for my $alt_idx (0 .. $start_rule->expressions()->$#*) {
            my $item = $self->_make_item($start_rule, $alt_idx, 0, 0, $semiring->one());
            $self->_chart_set(\@chart, 0, $item->{core_id}, 0, [$item, $alt_idx]);
        }

        # GC tracking
        my $oldest_live_pos = 0;

        # Process each chart position
        for my $pos (0 .. $n) {
            $_gc_current_pos = $pos;
            $_gc_future_min = undef;  # Reset for this position

            # Build agenda from all entries at this position
            my @agenda;
            for my $core_hash (values $chart[$pos]->%*) {
                push @agenda, values $core_hash->%*;
            }
            my %processed;

            while (my $entry = shift @agenda) {
                my ($item, $alt_idx) = $entry->@*;
                my $core_id = $item->{core_id};
                my $origin = $item->{origin};

                # Skip if already processed (pack for fast hash key)
                my $pkey = pack('NN', $core_id, $origin);
                next if $processed{$pkey};
                $processed{$pkey} = true;

                # Re-read from chart: the value may have been updated by a
                # merge (via add() in _complete or _advance_from_completed)
                # since this entry was pushed to the agenda. Using the chart
                # value ensures we process the fully-merged value, not the
                # stale pre-merge value from the agenda entry.
                ($item, $alt_idx) = $self->_chart_get(\@chart, $pos, $core_id, $origin)->@*;

                if ($self->_is_complete($item, $alt_idx)) {
                    # Apply on_complete for completed rule before propagating
                    my $completed_value = $semiring->on_complete($item, $alt_idx, $pos);
                    $item = { %$item, value => $completed_value };
                    # Update the chart entry with the action-applied value
                    $self->_chart_set(\@chart, $pos, $core_id, $origin, [$item, $alt_idx]);
                    # Index this completed item for _advance_from_completed lookups
                    my $c_rule = $item->{rule}->name();
                    my $c_origin = $item->{origin};
                    $completed_at{$c_rule}{$c_origin}{$pos} //= [];
                    push $completed_at{$c_rule}{$c_origin}{$pos}->@*, [$core_id, $origin];
                    # Skip propagation of zero-valued completions. A zero
                    # from on_complete (e.g. TypeInference rejecting a
                    # keyword-as-Identifier) must not poison parent items
                    # via multiply — the valid parse path will supply
                    # the correct value independently.
                    next if $semiring->is_zero($completed_value);
                    # Complete
                    $self->_complete($item, $alt_idx, $pos, \@chart, \@agenda);
                } else {
                    my $symbol = $self->_symbol_after_dot($item, $alt_idx);

                    if ($symbol->is_reference()) {
                        # Index this item as waiting for the nonterminal
                        my $w_rule = $symbol->value();
                        $waiting_for{$w_rule}{$pos} //= [];
                        push $waiting_for{$w_rule}{$pos}->@*, [$core_id, $origin];
                        # Predict
                        $self->_predict($symbol, $pos, \@chart, \@agenda);
                        # Advance from already-completed items at this position.
                        # When a nullable nonterminal (e.g. _) appears multiple
                        # times in a rule, the second prediction is suppressed
                        # (already predicted). The completion that ran earlier
                        # couldn't advance this waiting item because it didn't
                        # exist yet. So we check for completed items now.
                        $self->_advance_from_completed(
                            $item, $alt_idx, $symbol, $pos, \@chart, \@agenda
                        );
                    } else {
                        # Scan (allow at end of input for zero-width matches)
                        $self->_scan($item, $alt_idx, $symbol, $pos, $input, \@chart, $n, \@agenda);
                    }
                }
            }

            # Safe-set chart GC: determine the safe floor by checking which
            # positions are still referenced by waiting_for entries.
            # _complete reads chart[$origin] to find waiting items, so any
            # position that has waiting items must stay alive.
            {
                my $safe_floor = $pos;
                # Find minimum position still referenced by waiting_for
                for my $rule_waits (values %waiting_for) {
                    for my $wait_pos (keys $rule_waits->%*) {
                        $safe_floor = $wait_pos if $wait_pos < $safe_floor;
                    }
                }
                # Also check future items placed by scanning
                if (defined $_gc_future_min && $_gc_future_min < $safe_floor) {
                    $safe_floor = $_gc_future_min;
                }
                for my $gc_pos ($oldest_live_pos .. $safe_floor - 1) {
                    next if $gc_pos >= $pos;
                    if (keys $chart[$gc_pos]->%*) {
                        $chart[$gc_pos] = {};
                        $_gc_stats{positions_freed}++;
                    }
                }
                $oldest_live_pos = $safe_floor if $safe_floor > $oldest_live_pos;
            }
        }

        # Check if we have a completed start rule spanning entire input
        for my $alt_idx (0 .. $start_rule->expressions()->$#*) {
            my $end_dot = scalar($start_rule->expressions()->[$alt_idx]->@*);
            my $core_id = $core_index->id_for($start_rule->name(), $alt_idx, $end_dot);

            if ($self->_chart_has(\@chart, $n, $core_id, 0)) {
                my $item = $self->_chart_get(\@chart, $n, $core_id, 0)->[0];
                return $item->{value};
            }
        }

        return undef;
    }

    # Parse input string, returns boolean indicating success
    method parse($input) {
        my $value = $self->_run_parse($input);
        return defined($value) ? !$semiring->is_zero($value) : false;
    }

    # Parse input string, returns raw semiring value (or undef on failure)
    method parse_value($input) {
        return $self->_run_parse($input);
    }

    # Predict: add items for all alternatives of a nonterminal using
    # pre-computed LR(0) DFA epsilon-closure prediction items.
    method _predict($symbol, $pos, $chart, $agenda) {
        my $rule_name = $symbol->value();
        my $prediction_items = $lr0_dfa->prediction_items_for($rule_name);
        return unless defined $prediction_items;

        for my $core_id ($prediction_items->@*) {
            unless ($self->_chart_has($chart, $pos, $core_id, $pos)) {
                my $info = $core_index->item_for($core_id);
                my $rule = $rule_table->{$info->{rule_name}};
                my $item = $self->_make_item($rule, $info->{alt_idx}, 0, $pos, $semiring->one());
                $self->_chart_set($chart, $pos, $core_id, $pos, [$item, $info->{alt_idx}]);
                push $agenda->@*, [$item, $info->{alt_idx}];
            }
        }
    }

    # Scan: match terminal and advance to next position
    method _scan($item, $alt_idx, $symbol, $pos, $input, $chart, $n, $agenda = undef) {
        my $pattern_str = $symbol->value();
        my $pattern = $regex_cache{$pattern_str} //= qr/$pattern_str/;
        my $end_pos = Chalk::Bootstrap::Terminal::match($input, $pos, $pattern);

        return unless defined $end_pos;

        # Capture matched text
        my $matched = substr($input, $pos, $end_pos - $pos);

        # Build $is_predicted callback for this position
        my $is_predicted = sub($rule_name) {
            return exists $waiting_for{$rule_name}{$pos};
        };

        # Ask semiring if scan should proceed
        return unless $semiring->should_scan($item, $alt_idx, $pos, $matched, $is_predicted);

        # Use on_scan to combine existing value with scan
        my $new_value = $semiring->on_scan($item, $alt_idx, $pos, $matched);

        # on_scan returns the combined result; check for zero (semiring rejected)
        return if $semiring->is_zero($new_value);

        # Advance dot
        my $new_item = $self->_make_item(
            $item->{rule},
            $alt_idx,
            $item->{dot} + 1,
            $item->{origin},
            $new_value
        );

        my $new_core_id = $new_item->{core_id};
        my $origin = $new_item->{origin};

        if ($self->_chart_has($chart, $end_pos, $new_core_id, $origin)) {
            # Merge with existing item using semiring add (create new item, don't mutate)
            my $existing = $self->_chart_get($chart, $end_pos, $new_core_id, $origin)->[0];
            my $merged_value = $semiring->add($existing->{value}, $new_item->{value});
            my $merged_item = $self->_make_item(
                $existing->{rule},
                $alt_idx,
                $existing->{dot},
                $existing->{origin},
                $merged_value,
            );
            $self->_chart_set($chart, $end_pos, $new_core_id, $origin, [$merged_item, $alt_idx]);
            # If zero-width match, add to current agenda for immediate processing
            if ($end_pos == $pos && $agenda) {
                push $agenda->@*, [$merged_item, $alt_idx];
            }
        } else {
            $self->_chart_set($chart, $end_pos, $new_core_id, $origin, [$new_item, $alt_idx]);
            # If zero-width match, add to current agenda for immediate processing
            if ($end_pos == $pos && $agenda) {
                push $agenda->@*, [$new_item, $alt_idx];
            }
        }
    }

    # Complete: combine completed items with items waiting for them.
    # Uses %waiting_for index for O(1) lookup instead of scanning the full chart.
    method _complete($completed_item, $completed_alt_idx, $pos, $chart, $agenda) {
        my $rule_name = $completed_item->{rule}->name();
        my $origin = $completed_item->{origin};

        # Look up items at origin that are waiting for this rule name
        my $waiting_refs = $waiting_for{$rule_name}{$origin};
        return unless defined $waiting_refs;

        for my $wref ($waiting_refs->@*) {
            my ($w_core_id, $w_origin) = $wref->@*;
            my $entry = $self->_chart_get($chart, $origin, $w_core_id, $w_origin);
            next unless defined $entry;
            my ($waiting_item, $waiting_alt_idx) = $entry->@*;

            # Advance the waiting item
            my $new_value = $semiring->multiply($waiting_item->{value}, $completed_item->{value});

            # Skip if multiply produced zero — don't propagate rejected
            # completions (e.g. keyword-as-Identifier) to parent items
            next if $semiring->is_zero($new_value);

            my $new_item = $self->_make_item(
                $waiting_item->{rule},
                $waiting_alt_idx,
                $waiting_item->{dot} + 1,
                $waiting_item->{origin},
                $new_value
            );

            my $new_core_id = $new_item->{core_id};
            my $new_origin = $new_item->{origin};

            if ($self->_chart_has($chart, $pos, $new_core_id, $new_origin)) {
                # Merge with existing item using semiring add (create new item, don't mutate)
                my $existing = $self->_chart_get($chart, $pos, $new_core_id, $new_origin)->[0];
                my $merged_value;
                try {
                    $merged_value = $semiring->add($existing->{value}, $new_item->{value});
                } catch ($e) {
                    my $rule_name = $existing->{rule}->name();
                    my $dot = $existing->{dot};
                    my $origin = $existing->{origin};
                    my $comp_rule = $completed_item->{rule}->name();
                    my $comp_origin = $completed_item->{origin};
                    die "Ambiguity in rule '$rule_name' (dot=$dot, origin=$origin, pos=$pos) "
                        . "completing='$comp_rule' (origin=$comp_origin): $e";
                }
                my $merged_item = $self->_make_item(
                    $existing->{rule},
                    $waiting_alt_idx,
                    $existing->{dot},
                    $existing->{origin},
                    $merged_value,
                );
                $self->_chart_set($chart, $pos, $new_core_id, $new_origin, [$merged_item, $waiting_alt_idx]);
            } else {
                $self->_chart_set($chart, $pos, $new_core_id, $new_origin, [$new_item, $waiting_alt_idx]);
                push $agenda->@*, [$new_item, $waiting_alt_idx];
            }
        }
    }

    # After prediction, check for already-completed items of the predicted
    # rule at the current position and advance the waiting item. This handles
    # nullable nonterminals (like whitespace _) appearing multiple times in a
    # rule — the second prediction is suppressed but the earlier completion
    # never saw this waiting item, so we combine them here.
    # Uses %completed_at index for O(1) lookup instead of scanning the full chart.
    method _advance_from_completed($item, $alt_idx, $symbol, $pos, $chart, $agenda) {
        my $rule_name = $symbol->value();

        # Look up completed items for this rule name with origin == pos at chart pos
        my $completed_refs = $completed_at{$rule_name}{$pos}{$pos};
        return unless defined $completed_refs;

        for my $cref ($completed_refs->@*) {
            my ($c_core_id, $c_origin) = $cref->@*;
            my $entry = $self->_chart_get($chart, $pos, $c_core_id, $c_origin);
            next unless defined $entry;
            my ($citem, $calt_idx) = $entry->@*;

            # Advance the waiting item past the completed reference
            my $new_value = $semiring->multiply($item->{value}, $citem->{value});

            # Skip if multiply produced zero — don't propagate rejected
            # completions to parent items
            next if $semiring->is_zero($new_value);

            my $new_item = $self->_make_item(
                $item->{rule},
                $alt_idx,
                $item->{dot} + 1,
                $item->{origin},
                $new_value
            );

            my $new_core_id = $new_item->{core_id};
            my $new_origin = $new_item->{origin};

            if ($self->_chart_has($chart, $pos, $new_core_id, $new_origin)) {
                my $existing = $self->_chart_get($chart, $pos, $new_core_id, $new_origin)->[0];
                my $merged_value = $semiring->add($existing->{value}, $new_item->{value});
                my $merged_item = $self->_make_item(
                    $existing->{rule},
                    $alt_idx,
                    $existing->{dot},
                    $existing->{origin},
                    $merged_value,
                );
                $self->_chart_set($chart, $pos, $new_core_id, $new_origin, [$merged_item, $alt_idx]);
            } else {
                $self->_chart_set($chart, $pos, $new_core_id, $new_origin, [$new_item, $alt_idx]);
                push $agenda->@*, [$new_item, $alt_idx];
            }
        }
    }
}
