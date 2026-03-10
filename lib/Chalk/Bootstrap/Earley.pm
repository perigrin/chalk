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

    # Leo items: {rule_name}{pos} = $leo_item
    # A Leo item represents a chain of deterministic completions,
    # reducing O(n) items per recursive chain to O(1).
    field %leo_items;

    # Whether the semiring supports Leo optimization (cached at construction)
    field $_leo_enabled;

    # Minimum position referenced by waiting_for entries and Leo item origins
    # (tracked incrementally to avoid O(n) scan at every GC step)
    field $_waiting_for_min;
    field $_leo_origin_min;

    # Scan result cache: {pos}{pattern_string} => $end_pos (or undef)
    # Avoids redundant regex matching when multiple items scan the same
    # terminal at the same position (28% of scans are duplicates, 93% fail).
    field %_scan_cache;

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

        # Cache whether Leo optimization is supported by this semiring
        $_leo_enabled = ($semiring->can('supports_leo') && $semiring->supports_leo()) ? true : false;

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

    # Chart access helpers. Chart structure: $chart[$pos][$core_id]{$origin} = [$item, $alt_idx]
    method _chart_has($chart, $pos, $core_id, $origin) {
        my $oh = $chart->[$pos][$core_id];
        return defined $oh && exists $oh->{$origin};
    }

    method _chart_get($chart, $pos, $core_id, $origin) {
        return $chart->[$pos][$core_id]{$origin};
    }

    method _chart_set($chart, $pos, $core_id, $origin, $entry) {
        ($chart->[$pos][$core_id] //= {})->{$origin} = $entry;
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

    # Advance an existing item by one dot position using cached integer mapping.
    # Avoids the string-join + hash lookup of id_for() by using advance().
    # Uses individual hash assignments instead of hashref literal to avoid
    # stale-value merge corruption in XS codegen.
    method _advance_item($item, $value) {
        my $new_core_id = $core_index->advance($item->{core_id});
        my $new_item = {};
        $new_item->{rule}    = $item->{rule};
        $new_item->{alt_idx} = $item->{alt_idx};
        $new_item->{core_id} = $new_core_id;
        $new_item->{dot}     = $item->{dot} + 1;
        $new_item->{origin}  = $item->{origin};
        $new_item->{value}   = $value;
        return $new_item;
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

        # Chart: array of arrays, where each entry is [$core_id]{$origin} => [$item, $alt_idx]
        my @chart = map { [] } (0 .. $n);

        # Reset secondary indexes for this parse
        %waiting_for = ();
        %completed_at = ();
        %leo_items = ();
        %_scan_cache = ();
        $_waiting_for_min = 0;
        $_leo_origin_min = undef;
        %_gc_stats = (positions_freed => 0);
        @_gc_min_origin_at = ();
        $_gc_current_pos = undef;
        $_gc_future_min = undef;

        # Find the start rule (first rule in grammar)
        my $start_rule = $grammar->[0];

        # Initialize chart[0] with start rule items (one per alternative)
        for my $alt_idx (0 .. $start_rule->expressions()->$#*) {
            my $item = $self->_make_item($start_rule, $alt_idx, 0, 0, $semiring->one());
            my $_ci = $item->{core_id};
            ($chart[0][$_ci] //= {})->{0} = [$item, $alt_idx];
            $_gc_min_origin_at[0] = 0 if !defined $_gc_min_origin_at[0];
        }

        # GC tracking
        my $oldest_live_pos = 0;

        # Process each chart position
        for my $pos (0 .. $n) {
            $_gc_current_pos = $pos;
            $_gc_future_min = undef;  # Reset for this position

            # Build agenda from all entries at this position
            my @agenda;
            for my $origin_hash ($chart[$pos]->@*) {
                next unless defined $origin_hash;
                push @agenda, values $origin_hash->%*;
            }
            my @processed;
            my %predicted_at;  # Track which rules have been predicted at this pos

            while (my $entry = shift @agenda) {
                my ($item, $alt_idx) = $entry->@*;
                my $core_id = $item->{core_id};
                my $origin = $item->{origin};

                # Skip if already processed (2D array avoids pack + hash lookup)
                # Uses explicit if-block instead of postfix next-if for XS
                # codegen compatibility (postfix next-if with && falls to eval_pv)
                my $p_slot = $processed[$core_id];
                if (defined $p_slot) {
                    next if $p_slot->[$origin];
                }
                $processed[$core_id] //= [];
                $processed[$core_id][$origin] = true;

                # Re-read from chart: the value may have been updated by a
                # merge (via add() in _complete or _advance_from_completed)
                # since this entry was pushed to the agenda. Using the chart
                # value ensures we process the fully-merged value, not the
                # stale pre-merge value from the agenda entry.
                # Uses explicit indexing instead of list destructuring for
                # XS codegen compatibility.
                my $chart_entry = $chart[$pos][$core_id]{$origin};
                $item = $chart_entry->[0];
                $alt_idx = $chart_entry->[1];

                if ($self->_is_complete($item, $alt_idx)) {
                    # Apply on_complete for completed rule before propagating
                    my $completed_value = $semiring->on_complete($item, $alt_idx, $pos);
                    $item = { %$item, value => $completed_value };
                    # Update the chart entry with the action-applied value
                    $chart[$pos][$core_id]{$origin} = [$item, $alt_idx];
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
                        my $w_rule = $symbol->value();

                        # Inline ? handling: create skip path that advances
                        # past the optional symbol without matching it.
                        # DFA prediction handles this for initially-predicted
                        # items (dot=0 advancement); this handles mid-rule
                        # optionals where the dot reaches B? during parsing.
                        if ($symbol->is_quantified() && $symbol->quantifier() eq '?') {
                            my $skip_value = $semiring->can('on_skip_optional')
                                ? $semiring->on_skip_optional($item, $alt_idx, $pos, $w_rule)
                                : $semiring->multiply($item->{value}, $semiring->one());
                            my $skip_is_zero = defined $skip_value ? $semiring->is_zero($skip_value) : true;
                            if (defined $skip_value && !$skip_is_zero) {
                                my $skip_item = $self->_advance_item($item, $skip_value);
                                my $skip_core = $skip_item->{core_id};
                                my $skip_oh = $chart[$pos][$skip_core];
                                if (defined $skip_oh && exists $skip_oh->{$origin}) {
                                    my $existing = $skip_oh->{$origin}->[0];
                                    my $merged = $semiring->add(
                                        $existing->{value}, $skip_value
                                    );
                                    my $merged_is_zero = $semiring->is_zero($merged);
                                    if (!$merged_is_zero) {
                                        my $merged_item = {
                                            %$existing, value => $merged
                                        };
                                        $chart[$pos][$skip_core]{$origin} = [$merged_item, $alt_idx];
                                        my $sp_slot = $processed[$skip_core];
                                        push @agenda, [$merged_item, $alt_idx]
                                            unless defined $sp_slot && $sp_slot->[$origin];
                                    }
                                } else {
                                    ($chart[$pos][$skip_core] //= {})->{$origin} = [$skip_item, $alt_idx];
                                    $_gc_min_origin_at[$pos] = $origin
                                        if !defined $_gc_min_origin_at[$pos] || $origin < $_gc_min_origin_at[$pos];
                                    push @agenda, [$skip_item, $alt_idx];
                                }
                            }
                        }

                        # Index this item as waiting for the nonterminal
                        $waiting_for{$w_rule}{$pos} //= [];
                        push $waiting_for{$w_rule}{$pos}->@*, [$core_id, $origin];
                        # Predict
                        $self->_predict($symbol, $pos, \@chart, \@agenda, \%predicted_at);
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
                        $self->_scan($item, $alt_idx, $symbol, $pos, $input, \@chart, $n, \@agenda, \%predicted_at);
                    }
                }
            }

            # Safe-set chart GC: determine the safe floor using incrementally
            # tracked minimum positions. _complete reads chart[$origin] to
            # find waiting items, so any position that has waiting items must
            # stay alive. $_waiting_for_min is updated when entries are added
            # to %waiting_for, avoiding O(n) scan per position.
            {
                my $safe_floor = $pos;
                # Use incrementally tracked minimums from waiting_for and Leo items
                $safe_floor = $_waiting_for_min
                    if defined $_waiting_for_min && $_waiting_for_min < $safe_floor;
                $safe_floor = $_leo_origin_min
                    if defined $_leo_origin_min && $_leo_origin_min < $safe_floor;
                # Also check future items placed by scanning
                if (defined $_gc_future_min && $_gc_future_min < $safe_floor) {
                    $safe_floor = $_gc_future_min;
                }
                for my $gc_pos ($oldest_live_pos .. $safe_floor - 1) {
                    next if $gc_pos >= $pos;
                    if ($chart[$gc_pos]->@*) {
                        $_gc_stats{positions_freed}++;
                        $chart[$gc_pos] = [];
                        delete $_scan_cache{$gc_pos};
                    }
                }
                $oldest_live_pos = $safe_floor if $safe_floor > $oldest_live_pos;
            }
        }

        # Check if we have a completed start rule spanning entire input
        for my $alt_idx (0 .. $start_rule->expressions()->$#*) {
            my $end_dot = scalar($start_rule->expressions()->[$alt_idx]->@*);
            my $core_id = $core_index->id_for($start_rule->name(), $alt_idx, $end_dot);

            my $end_oh = $chart[$n][$core_id];
            if (defined $end_oh && exists $end_oh->{0}) {
                my $item = $end_oh->{0}->[0];
                return $item->{value};
            }
        }

        return undef;
    }

    # Parse input string, returns boolean indicating success
    method parse($input) {
        my $value = $self->_run_parse($input);
        return false unless defined $value;
        return $semiring->is_zero($value) ? false : true;
    }

    # Parse input string, returns raw semiring value (or undef on failure)
    method parse_value($input) {
        return $self->_run_parse($input);
    }

    # Predict: add items for all alternatives of a nonterminal using
    # pre-computed LR(0) DFA epsilon-closure prediction items.
    # The DFA provides [$core_id, $skip_symbols] pairs where $skip_symbols
    # lists ?-quantified symbol names skipped to reach that dot position
    # (Aycock nullable optimization). For dot>0 items, on_skip_optional is
    # called to create SemanticAction placeholders for each skipped symbol.
    # Tracks which rules have been predicted at each position to avoid
    # re-iterating the prediction set on redundant calls.
    method _predict($symbol, $pos, $chart, $agenda, $predicted_at = undef) {
        my $rule_name = $symbol->value();

        # Skip if this rule was already predicted at this position
        if (defined $predicted_at) {
            return if $predicted_at->{$rule_name};
            $predicted_at->{$rule_name} = true;
        }

        my $prediction_items = $lr0_dfa->prediction_items_for($rule_name);
        return unless defined $prediction_items;

        for my $pred_entry ($prediction_items->@*) {
            my ($core_id, $skip_symbols) = $pred_entry->@*;
            unless ($self->_chart_has($chart, $pos, $core_id, $pos)) {
                my $info = $core_index->item_for($core_id);
                my $dot = $info->{dot};
                my $rule = $rule_table->{$info->{rule_name}};

                # Build initial value. For dot>0 items with skipped ? symbols,
                # call on_skip_optional for each skipped symbol to create
                # SemanticAction placeholder contexts.
                my $value = $semiring->one();
                if ($skip_symbols && $skip_symbols->@*) {
                    for my $sym_name ($skip_symbols->@*) {
                        if ($semiring->can('on_skip_optional')) {
                            my $synth = { value => $value, rule => $rule };
                            $value = $semiring->on_skip_optional(
                                $synth, $info->{alt_idx}, $pos, $sym_name
                            );
                            last if !defined $value || $semiring->is_zero($value);
                        } else {
                            $value = $semiring->multiply($value, $semiring->one());
                        }
                    }
                    next if !defined $value || $semiring->is_zero($value);
                }

                my $item = $self->_make_item($rule, $info->{alt_idx}, $dot, $pos, $value);
                $self->_chart_set($chart, $pos, $core_id, $pos, [$item, $info->{alt_idx}]);
                push $agenda->@*, [$item, $info->{alt_idx}];
            }
        }
    }

    # Scan: match terminal and advance to next position
    method _scan($item, $alt_idx, $symbol, $pos, $input, $chart, $n, $agenda = undef, $predicted_at = undef) {
        my $pattern_str = $symbol->value();

        # Check scan result cache before attempting regex match
        my $end_pos;
        if (exists $_scan_cache{$pos} && exists $_scan_cache{$pos}{$pattern_str}) {
            $end_pos = $_scan_cache{$pos}{$pattern_str};
        } else {
            my $pattern = $regex_cache{$pattern_str} //= qr/$pattern_str/;
            $end_pos = Chalk::Bootstrap::Terminal::match($input, $pos, $pattern);
            $_scan_cache{$pos}{$pattern_str} = $end_pos;
        }

        return unless defined $end_pos;

        # Capture matched text
        my $matched = substr($input, $pos, $end_pos - $pos);

        # Pass predicted_at hashref from _run_parse to should_scan.
        # predicted_at tracks which rules have been predicted at this position,
        # which is exactly what should_scan needs for keyword rejection.
        # Using the caller's hashref avoids iterating field hash keys (which
        # the XS codegen cannot handle).
        my $is_predicted = $predicted_at // {};

        # Ask semiring if scan should proceed
        return unless $semiring->should_scan($item, $alt_idx, $pos, $matched, $is_predicted);

        # Use on_scan to combine existing value with scan
        my $new_value = $semiring->on_scan($item, $alt_idx, $pos, $matched);

        # on_scan returns the combined result; check for zero (semiring rejected)
        return if $semiring->is_zero($new_value);

        # Advance dot
        my $new_item = $self->_advance_item($item, $new_value);

        my $new_core_id = $new_item->{core_id};
        my $origin = $new_item->{origin};

        if ($self->_chart_has($chart, $end_pos, $new_core_id, $origin)) {
            # Merge with existing item using semiring add (create new item, don't mutate)
            my $existing = $self->_chart_get($chart, $end_pos, $new_core_id, $origin)->[0];
            my $merged_value = $semiring->add($existing->{value}, $new_item->{value});
            my $merged_item = { %$existing, value => $merged_value };
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
    # Leo optimization: when a completion is deterministic (exactly one waiting
    # item, at penultimate position), create a Leo item that represents the
    # entire chain of completions in O(1) instead of O(n).
    method _complete($completed_item, $completed_alt_idx, $pos, $chart, $agenda) {
        my $rule_name = $completed_item->{rule}->name();
        my $origin = $completed_item->{origin};

        # Leo resolution: check if a Leo item exists for this rule at origin.
        # Leo items are keyed by (rule_name, origin) where origin is where the
        # waiting items live. When a completion has this origin, the Leo item
        # shortcuts the entire chain to the top.
        # Leo is only used when the semiring supports it (on_complete must be
        # trivial / identity for correctness — non-trivial on_complete would
        # be skipped for intermediate chain steps).
        my $leo_resolved_core_id;
        my $leo_resolved_origin;
        if ($_leo_enabled
            && (my $leo = $leo_items{$rule_name}{$origin})) {
            my $combined = $semiring->multiply($leo->{value}, $completed_item->{value});
            unless ($semiring->is_zero($combined)) {
                my $top = $leo->{top_item};
                my $top_alt = $leo->{top_alt};
                my $new_item = $self->_advance_item($top, $combined);
                my $new_core_id = $new_item->{core_id};
                my $new_origin = $new_item->{origin};

                if ($self->_chart_has($chart, $pos, $new_core_id, $new_origin)) {
                    my $existing = $self->_chart_get($chart, $pos, $new_core_id, $new_origin)->[0];
                    my $merged_value;
                    try {
                        $merged_value = $semiring->add($existing->{value}, $new_item->{value});
                    } catch ($e) {
                        die "Ambiguity resolving Leo item for '$rule_name': $e";
                    }
                    my $merged_item = { %$existing, value => $merged_value };
                    $self->_chart_set($chart, $pos, $new_core_id, $new_origin, [$merged_item, $top_alt]);
                } else {
                    $self->_chart_set($chart, $pos, $new_core_id, $new_origin, [$new_item, $top_alt]);
                    push $agenda->@*, [$new_item, $top_alt];
                }
            }
            # Track which waiting item the Leo covered so we skip it below.
            # Use the immediate waiting item identity (wait_core_id/wait_origin),
            # not top_item — after chain extension, top_item may be at a distant
            # origin that doesn't match the actual waiting item at this position.
            $leo_resolved_core_id = $leo->{wait_core_id};
            $leo_resolved_origin = $leo->{wait_origin};
        }

        # Look up items at origin that are waiting for this rule name
        my $waiting_refs = $waiting_for{$rule_name}{$origin};
        return unless defined $waiting_refs;

        # Count non-zero waiting items and track the single candidate for Leo
        my $eligible_count = 0;
        my $leo_candidate_entry;
        my $leo_candidate_value;

        for my $wref ($waiting_refs->@*) {
            my ($w_core_id, $w_origin) = $wref->@*;

            # Skip the waiting item already handled by Leo resolution above
            next if defined $leo_resolved_core_id
                && $w_core_id == $leo_resolved_core_id
                && $w_origin  == $leo_resolved_origin;

            my $entry = $self->_chart_get($chart, $origin, $w_core_id, $w_origin);
            next unless defined $entry;
            my ($waiting_item, $waiting_alt_idx) = $entry->@*;

            # Advance the waiting item
            my $new_value = $semiring->multiply($waiting_item->{value}, $completed_item->{value});

            # Skip if multiply produced zero — don't propagate rejected
            # completions (e.g. keyword-as-Identifier) to parent items
            next if $semiring->is_zero($new_value);

            my $new_item = $self->_advance_item($waiting_item, $new_value);

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
                my $merged_item = { %$existing, value => $merged_value };
                $self->_chart_set($chart, $pos, $new_core_id, $new_origin, [$merged_item, $waiting_alt_idx]);
            } else {
                $self->_chart_set($chart, $pos, $new_core_id, $new_origin, [$new_item, $waiting_alt_idx]);
                push $agenda->@*, [$new_item, $waiting_alt_idx];
            }

            # Track Leo eligibility: count non-zero waiting items
            $eligible_count++;
            $leo_candidate_entry = $entry;
            $leo_candidate_value = $new_value;
        }

        # Leo creation: if exactly one waiting item produced a non-zero result
        # AND no Leo item was already resolved (deterministic = total 1 waiter),
        # and advancing it would make it complete (penultimate position),
        # create a Leo item keyed at the origin position.
        if ($eligible_count == 1 && !defined $leo_resolved_core_id
            && $_leo_enabled) {
            my ($waiting_item, $waiting_alt_idx) = $leo_candidate_entry->@*;
            my $advanced_dot = $waiting_item->{dot} + 1;
            my $alt = $waiting_item->{rule}->expressions()->[$waiting_alt_idx];

            # Penultimate check: after advancing, the item would be complete
            if ($advanced_dot >= scalar $alt->@*) {
                # Check if there's already a Leo item in the chain we can extend
                my $w_rule_name = $waiting_item->{rule}->name();
                my $top_item;
                my $top_alt;
                my $chain_value;

                if (my $parent_leo = $leo_items{$w_rule_name}{$waiting_item->{origin}}) {
                    # Extend existing Leo chain: use the top of the parent chain
                    $top_item = $parent_leo->{top_item};
                    $top_alt = $parent_leo->{top_alt};
                    $chain_value = $semiring->multiply($parent_leo->{value}, $completed_item->{value});
                } else {
                    # Start new Leo chain
                    $top_item = $waiting_item;
                    $top_alt = $waiting_alt_idx;
                    $chain_value = $leo_candidate_value;
                }

                # Store Leo item at $origin (where the waiting items live).
                # Future completions of $rule_name with this origin will resolve
                # the chain in O(1).
                # wait_core_id/wait_origin track the immediate waiting item
                # so _complete can skip it (distinct from top_item after chain extension).
                $leo_items{$rule_name}{$origin} = {
                    leo          => true,
                    rule_name    => $rule_name,
                    origin       => $top_item->{origin},
                    value        => $chain_value,
                    top_item     => $top_item,
                    top_alt      => $top_alt,
                    wait_core_id => $waiting_item->{core_id},
                    wait_origin  => $waiting_item->{origin},
                };
                # Track minimum Leo origin for GC
                $_leo_origin_min = $top_item->{origin}
                    if !defined $_leo_origin_min || $top_item->{origin} < $_leo_origin_min;
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

            my $new_item = $self->_advance_item($item, $new_value);

            my $new_core_id = $new_item->{core_id};
            my $new_origin = $new_item->{origin};

            if ($self->_chart_has($chart, $pos, $new_core_id, $new_origin)) {
                my $existing = $self->_chart_get($chart, $pos, $new_core_id, $new_origin)->[0];
                my $merged_value = $semiring->add($existing->{value}, $new_item->{value});
                my $merged_item = { %$existing, value => $merged_value };
                $self->_chart_set($chart, $pos, $new_core_id, $new_origin, [$merged_item, $alt_idx]);
            } else {
                $self->_chart_set($chart, $pos, $new_core_id, $new_origin, [$new_item, $alt_idx]);
                push $agenda->@*, [$new_item, $alt_idx];
            }
        }
    }
}
