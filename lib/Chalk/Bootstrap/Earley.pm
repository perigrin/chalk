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

    # Source file path for diagnostics (set per parse_value call)
    field $_parse_file;
    field $_last_active_pos;
    field $_diag_expected;

    # Build a lookup table for rules by name
    field $rule_table;

    # Core item index: maps (rule_name, alt_idx, dot) to small integer IDs
    field $core_index :reader;

    # LR(0) DFA for prediction clustering
    field $lr0_dfa;

    # Secondary indexes for O(1) lookup during complete/advance
    # Reset at the start of each parse.
    # completed_at: {rule_name}{origin_pos}{chart_pos} = [[core_id, origin], ...] — completed items
    field %completed_at;

    # Precomputed from CoreItemIndex: maps each nonterminal name to the list of
    # core item IDs where the dot is immediately before that nonterminal.
    # I.e., for nonterminal R, _waiting_core_ids{R} = [id, ...] where each id
    # represents an item of the form [B -> alpha . R beta].
    # Built once at construction time; never mutated during parsing.
    field %_waiting_core_ids;

    # Leo items: {rule_name}{pos} = $leo_item
    # A Leo item represents a chain of deterministic completions,
    # reducing O(n) items per recursive chain to O(1).
    field %leo_items;

    # Whether the semiring supports Leo optimization (cached at construction)
    field $_leo_enabled;

    # Minimum Leo item origin position
    # (tracked incrementally to avoid O(n) scan at every GC step)
    field $_leo_origin_min;

    # Scan result cache: {pos}{pattern_string} => $end_pos (or undef)
    # Avoids redundant regex matching when multiple items scan the same
    # terminal at the same position (28% of scans are duplicates, 93% fail).
    field %_scan_cache;

    # Compiled regex cache: pattern_string => qr// object
    field %regex_cache;

    # GC statistics for the most recent parse
    field %_gc_stats;


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

        # Precompute %_waiting_core_ids: for each nonterminal R, collect all
        # core item IDs where the dot immediately precedes R.
        for my $id (0 .. $core_index->count() - 1) {
            my $info = $core_index->item_for($id);
            my $rule = $rule_table->{$info->{rule_name}};
            my $rhs  = $rule->expressions()->[$info->{alt_idx}];
            my $dot  = $info->{dot};
            if ($dot < scalar($rhs->@*)) {
                my $sym = $rhs->[$dot];
                if ($sym->is_reference()) {
                    $_waiting_core_ids{$sym->value()} //= [];
                    push $_waiting_core_ids{$sym->value()}->@*, $id;
                }
            }
        }
    }

    # Precomputed lookup: nonterminal name => arrayref of core item IDs where
    # the dot is immediately before that nonterminal.
    method waiting_core_ids() { return \%_waiting_core_ids; }

    # GC statistics accessor
    method gc_stats() {
        return \%_gc_stats;
    }

    # Detailed parse profiling — enabled by setting $ENV{EARLEY_PROFILE}
    field %_profile_data;
    method profile_data() { return \%_profile_data; }

    # Aycock Ch6: check if an Earley set is "safe" — locally unambiguous.
    # A safe set allows freeing all chart positions between the previous
    # safe set and this one.
    # Properties checked:
    #   1. At least one final (completed) item exists
    #   2. No non-final item competes for the same last symbol as a final item
    #   3. No nullable (empty rule) final items
    # Check whether position $pos is an Aycock safe set (Chapter 6).
    # A position is safe when there is no ambiguity about what was just
    # recognized, so the chart window before it can be freed.
    #
    # Three properties must hold (Aycock §6.2):
    #   Property 1: at least one final item (completed rule) at this position.
    #   Property 2: no non-final item's last-consumed symbol matches any final
    #               item's last symbol. "Last-consumed" = symbol before the dot
    #               (dot > 0 items only; predicted items with dot=0 have no
    #               consumed symbol and cannot conflict).
    #   Property 3: no final item resulted from an empty (nullable) rule.
    #
    # Note: left-recursive list grammars `A ::= A B | B` produce safe-set
    # boundaries at each `B` completion because the in-progress item
    # `A -> A . B` has last_consumed=`A`, which is never in the final items'
    # last_symbols set (those contain `B` or whatever B ends with).
    # Right-recursive grammars `A ::= B A | B` do NOT produce safe-set
    # boundaries because the in-progress item `A -> B . A` has
    # last_consumed=`B`, which conflicts with the base-case `A -> B .`
    # whose last_symbol is also `B`.
    method _is_safe_set($chart, $pos) {
        my @final_items;
        my %final_last_symbols;

        # Pass 1: collect final items and their last symbols
        for my $oh ($chart->[$pos]->@*) {
            next unless defined $oh;
            for my $entry (values $oh->%*) {
                my $item    = $entry->[0];
                my $alt_idx = $entry->[1];
                next unless $self->_is_complete($item, $alt_idx);

                my $rhs = $item->{rule}->expressions()->[$alt_idx];
                # Property 3: reject empty-rule completions
                return false if scalar($rhs->@*) == 0;

                push @final_items, $item;
                $final_last_symbols{$rhs->[-1]->value()} = 1 if $rhs->@*;
            }
        }

        # Property 1: must have at least one final item
        return false unless @final_items;

        if ($ENV{EARLEY_SAFE_DEBUG}) {
            warn sprintf("SAFE_SET_TRACE pos=%d final_count=%d last_syms=%s\n",
                $pos, scalar @final_items, join(',', sort keys %final_last_symbols));
        }

        # Pass 2: check Property 2 — no non-final item at this position is
        # expecting a symbol that a final item just completed over.
        # This checks the symbol AFTER the dot (the next expected symbol),
        # which catches both:
        #   - in-progress items (dot > 0) that have consumed up to a
        #     symbol that conflicts with a final item's last symbol
        #   - predicted items (dot = 0) that expect the same symbol as
        #     a final item's last symbol (indicating ambiguity about
        #     whether the symbol was "consumed" or "expected next")
        #
        # The more liberal "last-consumed" (symbol before dot) check from
        # Aycock's spec is valid in theory but allows false safe-sets
        # for grammars with zero-matching terminals (like /(?:\s|#[^\n]*)*/)
        # because predicted items at dot=0 are skipped, missing cases where
        # a newly predicted rule expects the same symbol a final rule matched.
        for my $oh ($chart->[$pos]->@*) {
            next unless defined $oh;
            for my $entry (values $oh->%*) {
                my $item    = $entry->[0];
                my $alt_idx = $entry->[1];
                next if $self->_is_complete($item, $alt_idx);

                my $sym = $self->_symbol_after_dot($item, $alt_idx);
                next unless defined $sym;

                if (exists $final_last_symbols{$sym->value()}) {
                    if ($ENV{EARLEY_SAFE_DEBUG}) {
                        warn sprintf("SAFE_SET_TRACE pos=%d Property2_fail rule=%s dot=%d sym_after_dot=%s\n",
                            $pos, $item->{rule}->name(), $item->{dot}, $sym->value());
                    }
                    return false;
                }
            }
        }

        if ($ENV{EARLEY_SAFE_DEBUG}) {
            warn sprintf("SAFE_SET pos=%d finals=%d\n", $pos, scalar @final_items);
        }
        return true;
    }

    # Debug: dump the minimum origin at each active chart position.
    # Called after parse to inspect what's keeping positions alive.
    method debug_chart_origins($chart_ref) {
        my @chart = $chart_ref->@*;
        my %origin_at_pos;
        for my $pos (0 .. $#chart) {
            next unless defined $chart[$pos] && $chart[$pos]->@*;
            my $min_origin = $pos;
            for my $oh ($chart[$pos]->@*) {
                next unless defined $oh;
                for my $o (keys $oh->%*) {
                    $min_origin = $o if $o < $min_origin;
                }
            }
            $origin_at_pos{$pos} = $min_origin;
        }
        return \%origin_at_pos;
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
    }

    # Earley item: {rule, alt_idx, core_id, dot, origin, value}
    # Uses individual hash assignments instead of hashref literal to avoid
    # stale-value merge corruption in XS codegen (same pattern as _advance_item).
    method _make_item($rule, $alt_idx, $dot, $origin, $value) {
        my $core_id = $core_index->id_for($rule->name(), $alt_idx, $dot);
        my $item = {};
        $item->{rule}    = $rule;
        $item->{alt_idx} = $alt_idx;
        $item->{core_id} = $core_id;
        $item->{dot}     = $dot;
        $item->{origin}  = $origin;
        $item->{value}   = $value;
        return $item;
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
        %completed_at = ();
        %leo_items = ();
        %_scan_cache = ();
        $_leo_origin_min = undef;
        %_gc_stats = (positions_freed => 0, safe_sets_found => 0);
        $_last_active_pos = 0;
        $_diag_expected = {};

        # Find the start rule (first rule in grammar)
        my $start_rule = $grammar->[0];

        # Initialize chart[0] with start rule items (one per alternative)
        for my $alt_idx (0 .. $start_rule->expressions()->$#*) {
            my $item = $self->_make_item($start_rule, $alt_idx, 0, 0, $semiring->one());
            my $_ci = $item->{core_id};
            ($chart[0][$_ci] //= {})->{0} = [$item, $alt_idx];
        }

        # GC tracking
        my $oldest_live_pos = 0;
        my $last_safe_pos = -1;  # Aycock safe-set tracking

        # Epoch GC: callback for statement-boundary sweeping
        my @pending_sweeps;
        my $on_epoch_commit = sub ($origin, $end) {
            push @pending_sweeps, [$origin, $end];
        };

        # Process each chart position
        for my $pos (0 .. $n) {
            # Build agenda from all entries at this position
            my @agenda;
            for my $origin_hash ($chart[$pos]->@*) {
                next unless defined $origin_hash;
                push @agenda, values $origin_hash->%*;
            }
            # Track furthest position with active items for diagnostics
            if (@agenda) {
                $_last_active_pos = $pos;
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
                    my $already = $p_slot->[$origin];
                    next if $already;
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
                    my $completed_value = $semiring->on_complete($item, $alt_idx, $pos, $on_epoch_commit);
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
                    next if !defined($completed_value) || $semiring->is_zero($completed_value);
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
                                        my $sp_done = defined $sp_slot && $sp_slot->[$origin];
                                        push @agenda, [$merged_item, $alt_idx]
                                            unless $sp_done;
                                    }
                                } else {
                                    ($chart[$pos][$skip_core] //= {})->{$origin} = [$skip_item, $alt_idx];
                                    push @agenda, [$skip_item, $alt_idx];
                                }
                            }
                        }

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

            # Snapshot expected tokens after full agenda processing.
            # At this point all predictions have been added so the chart
            # contains items waiting for their next symbol — exactly the
            # set of tokens that would allow parsing to continue.
            # Snapshot expected tokens after full agenda processing.
            # At this point all predictions have been added so the chart
            # contains items waiting for their next symbol — exactly the
            # set of tokens that would allow parsing to continue.
            if ($pos == $_last_active_pos) {
                $_diag_expected = {};
                for my $origin_hash ($chart[$pos]->@*) {
                    next unless defined $origin_hash;
                    for my $entry (values $origin_hash->%*) {
                        # Explicit indexing for XS codegen compatibility
                        # (list destructuring $entry->@* segfaults in XS)
                        my $diag_item = $entry->[0];
                        my $diag_alt = $entry->[1];
                        if (!$self->_is_complete($diag_item, $diag_alt)) {
                            my $sym = $self->_symbol_after_dot($diag_item, $diag_alt);
                            if (!$sym->is_reference()) {
                                $_diag_expected->{$sym->value()} = 1;
                            }
                        }
                    }
                }
            }

            # Epoch GC: drain pending sweeps after position is fully processed
            if (@pending_sweeps) {
                for my $sweep (@pending_sweeps) {
                    my ($sweep_origin, $sweep_end) = $sweep->@*;
                    # Phase 1: null values for epoch-internal items.
                    # Skip the origin position — it has parent rule items
                    # (Program, StatementList) that span beyond this epoch.
                    for my $sp ($sweep_origin + 1 .. $sweep_end - 1) {
                        next if $sp >= $pos;  # don't sweep current position
                        my $slot = $chart[$sp];
                        next unless defined $slot && $slot->@*;
                        for my $oh ($slot->@*) {
                            next unless defined $oh;
                            for my $ok (keys $oh->%*) {
                                next unless $ok >= $sweep_origin;
                                $oh->{$ok}->[0]->{value} = undef
                                    if defined $oh->{$ok}->[0]->{value};
                            }
                        }
                    }
                    # Phase 2: compact positions where all values are null
                    for my $sp ($sweep_origin + 1 .. $sweep_end - 1) {
                        next if $sp >= $pos;
                        my $slot = $chart[$sp];
                        next unless defined $slot && $slot->@*;
                        my $all_null = true;
                        SLOT_CHECK: for my $oh ($slot->@*) {
                            next unless defined $oh;
                            for my $entry (values $oh->%*) {
                                if (defined $entry->[0]->{value}) {
                                    $all_null = false;
                                    last SLOT_CHECK;
                                }
                            }
                        }
                        if ($all_null) {
                            $chart[$sp] = [];
                            delete $_scan_cache{$sp};
                            $_gc_stats{positions_freed}++;
                        }
                    }
                }
                @pending_sweeps = ();
            }

            # Aycock safe-set GC: if this position is a safe set, free
            # all chart positions between the previous safe set and this one.
            # Only positions strictly interior to the window are freed;
            # the safe-set boundary positions themselves are kept alive.
            #
            # Safety guard: find the minimum origin referenced by any item
            # at the current position. Only positions strictly below this
            # minimum (but within the window) can be freed. This prevents
            # freeing positions that active items (at pos) reference as origins,
            # which would cause _complete to fail silently when looking up
            # chart[origin] for those items.
            if ($self->_is_safe_set(\@chart, $pos)) {
                if ($last_safe_pos >= 0 && $pos > $last_safe_pos + 1) {
                    # Find the minimum origin referenced by any OPEN item
                    # across ALL chart positions in the candidate window
                    # (last_safe_pos+1 .. pos). This includes items at the
                    # current position (pos) AND at intermediate positions —
                    # any open item referencing an origin within the window
                    # will need that origin position to be live when it
                    # eventually completes and _complete looks up chart[origin].
                    #
                    # Final items have already fired _complete and no longer
                    # need their origin positions. Only OPEN items require
                    # their origin to remain live.
                    my $min_window_origin = $pos;
                    for my $check_pos ($last_safe_pos + 1 .. $pos) {
                        next unless defined $chart[$check_pos] && $chart[$check_pos]->@*;
                        for my $cid (0 .. $#{ $chart[$check_pos] }) {
                            my $oh = $chart[$check_pos][$cid];
                            next unless defined $oh;
                            for my $org (keys $oh->%*) {
                                next unless $org > $last_safe_pos && $org < $pos;
                                next unless $org < $min_window_origin;
                                my $entry = $oh->{$org};
                                next unless defined $entry;
                                my ($it, $ai) = $entry->@*;
                                # Skip final items — they've already used their origin
                                next if $self->_is_complete($it, $ai);
                                $min_window_origin = $org;
                            }
                        }
                    }
                    # Only free positions strictly below min_window_origin.
                    # This preserves positions that items at pos reference
                    # as their origins (needed by _complete lookups).
                    my $free_end = $min_window_origin - 1;
                    for my $sp ($last_safe_pos + 1 .. $free_end) {
                        if (defined $chart[$sp] && $chart[$sp]->@*) {
                            $chart[$sp] = [];
                            delete $_scan_cache{$sp};
                            $_gc_stats{positions_freed}++;
                        }
                        # Clean up completed_at entries at freed positions
                        for my $rule_name (keys %completed_at) {
                            for my $origin (keys $completed_at{$rule_name}->%*) {
                                delete $completed_at{$rule_name}{$origin}{$sp};
                            }
                            delete $completed_at{$rule_name}{$sp};
                        }
                    }
                    if ($ENV{EARLEY_SAFE_DEBUG}) {
                        warn sprintf("SAFE_SET_WINDOW pos=%d last_safe=%d min_window_origin=%d free_end=%d freed=%d\n",
                            $pos, $last_safe_pos, $min_window_origin, $free_end,
                            $free_end >= $last_safe_pos + 1 ? $free_end - $last_safe_pos : 0);
                    }
                    $oldest_live_pos = $last_safe_pos
                        if $last_safe_pos > $oldest_live_pos;
                }
                $last_safe_pos = $pos;
                $_gc_stats{safe_sets_found}++;
            }

            # Debug: compute true minimum origin across all active positions
            if ($ENV{EARLEY_ORIGIN_DEBUG} && $pos > 0 && $pos % 10 == 0) {
                my $true_min = $pos;
                my $min_at_q = -1;
                for my $q ($oldest_live_pos .. $pos) {
                    next unless defined $chart[$q] && $chart[$q]->@*;
                    for my $oh ($chart[$q]->@*) {
                        next unless defined $oh;
                        for my $o (keys $oh->%*) {
                            if ($o < $true_min) {
                                $true_min = $o;
                                $min_at_q = $q;
                            }
                        }
                    }
                }
                warn sprintf("ORIGIN_DEBUG pos=%d true_min=%d (at q=%d) oldest_live=%d could_free=%d\n",
                    $pos, $true_min, $min_at_q, $oldest_live_pos,
                    $true_min - $oldest_live_pos);
            }

            # Profiling: track chart size and live positions per position
            if ($ENV{EARLEY_PROFILE}) {
                my $items_at_pos = 0;
                for my $oh ($chart[$pos]->@*) {
                    next unless defined $oh;
                    $items_at_pos += scalar keys $oh->%*;
                }
                $_profile_data{total_items} += $items_at_pos;
                if ($items_at_pos > ($_profile_data{max_items_at_pos} // 0)) {
                    $_profile_data{max_items_at_pos} = $items_at_pos;
                    $_profile_data{max_items_pos} = $pos;
                }
                $_profile_data{live_positions} = $pos - $oldest_live_pos + 1;
                $_profile_data{last_pos} = $pos;
                # Sample every 1000 positions
                if ($pos % 1000 == 0 && $pos > 0) {
                    my $rss = 0;
                    if (open my $sf, '<', '/proc/self/status') {
                        while (<$sf>) { $rss = $1 if /VmRSS:\s+(\d+)/ }
                        close $sf;
                    }
                    warn sprintf("PROFILE pos=%d items_here=%d total=%d max=%d live_span=%d rss=%dkB\n",
                        $pos, $items_at_pos, $_profile_data{total_items},
                        $_profile_data{max_items_at_pos}, $_profile_data{live_positions}, $rss);
                }
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

    # Parse input string, returns raw semiring value (or undef on failure).
    # Optional $file param shown in diagnostic on failure.
    method parse_value($input, $file = undef) {
        $_parse_file = $file;
        my $result = $self->_run_parse($input);
        if (!defined $result) {
            $self->_emit_parse_diagnostic($input, $_last_active_pos);
        }
        return $result;
    }

    # Extract expected tokens and emit a Rust-style parse error diagnostic.
    # Called from parse_value on failure. Delegates to _format_parse_error
    # which does the actual formatting and warn() output.
    method _emit_parse_diagnostic($input, $last_active_pos) {
        $self->_format_parse_error($input, $last_active_pos);
    }

    # Format a Rust-style parse error diagnostic and warn it to STDERR.
    # Uses $_diag_expected field (populated by _run_parse before returning).
    method _format_parse_error($input, $last_active_pos) {
        my $file = $_parse_file;
        $file = '<input>' if !defined $file;
        my $n = length($input);

        # Calculate line and column from byte position
        my $line_num = 1;
        my $col = 1;
        for my $i (0 .. $last_active_pos - 1) {
            if (substr($input, $i, 1) eq "\n") {
                $line_num++;
                $col = 1;
            } else {
                $col++;
            }
        }

        # Extract source lines around failure position
        my @lines;
        my $line_start = 0;
        for my $j (0 .. $n - 1) {
            if (substr($input, $j, 1) eq "\n") {
                push @lines, substr($input, $line_start, $j - $line_start);
                $line_start = $j + 1;
            }
        }
        if ($line_start <= $n) {
            push @lines, substr($input, $line_start);
        }

        # Context window around failure
        my $context_radius = 2;
        my $start_idx = $line_num - $context_radius - 1;
        $start_idx = 0 if $start_idx < 0;
        my $end_idx = $line_num + $context_radius - 1;
        $end_idx = $#lines if $end_idx > $#lines;
        my $num_width = length($end_idx + 1);

        # Build source context
        my @context;
        for my $i ($start_idx .. $end_idx) {
            my $display_num = $i + 1;
            my $num_str = "$display_num";
            my $pad_needed = $num_width - length($num_str);
            my $padded = $pad_needed > 0 ? (' ' x $pad_needed) . $num_str : $num_str;
            my $src_line = $lines[$i];
            push @context, "$padded | $src_line";
            # Add caret line for the failure line
            if ($display_num == $line_num) {
                my $padding = ' ' x $num_width;
                my $spaces = $col > 1 ? (' ' x ($col - 1)) : '';
                push @context, "$padding | $spaces^";
            }
        }

        # Format expected tokens (sort, truncate at 10)
        my @expected = sort keys $_diag_expected->%*;
        my $expected_str;
        my $exp_count = scalar(@expected);
        if ($exp_count > 10) {
            my @first_ten;
            for my $ei (0 .. 9) {
                push @first_ten, $expected[$ei];
            }
            $expected_str = join(', ', @first_ten) . ', ...';
        } elsif ($exp_count > 0) {
            $expected_str = join(', ', @expected);
        } else {
            $expected_str = '(none)';
        }

        # Progress note

        # Assemble Rust-style diagnostic
        my $msg = "error: parse failed at line $line_num, column $col\n";
        $msg .= "  --> $file:$line_num:$col\n";
        $msg .= ' ' x ($num_width) . " |\n";
        for my $line (@context) {
            $msg .= "$line\n";
        }
        $msg .= ' ' x ($num_width) . " |\n";
        $msg .= "   = expected: $expected_str\n";
        $msg .= "   = note: parsing stopped at $last_active_pos of $n bytes\n";

        warn $msg;
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
    # Uses %_waiting_core_ids (precomputed at construction) to identify which
    # core item IDs can be waiting for the completed nonterminal, then scans
    # the chart at the completion origin to find all live waiting items.
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

        # Look up items waiting for this rule name via chart-based scan.
        # %_waiting_core_ids{$rule_name} lists the core item IDs where the dot
        # is immediately before $rule_name. We scan chart[$origin][core_id] for
        # each such core_id to find all live waiting items (keyed by w_origin).
        my $chart_waiting_ids = $_waiting_core_ids{$rule_name};
        return unless defined $chart_waiting_ids;

        # Count non-zero waiting items and track the single candidate for Leo
        my $eligible_count = 0;
        my $leo_candidate_entry;
        my $leo_candidate_value;

        for my $w_core_id ($chart_waiting_ids->@*) {
            my $oh = $chart->[$origin][$w_core_id];
            next unless defined $oh;

            for my $w_origin (keys $oh->%*) {
                # Skip the waiting item already handled by Leo resolution above.
                # Uses explicit if-block because postfix `next if ... &&` miscompiles
                # in XS codegen (garbled eval_pv fallback).
                if (defined $leo_resolved_core_id) {
                    next if $w_core_id == $leo_resolved_core_id
                        && $w_origin  == $leo_resolved_origin;
                }

                my $entry = $oh->{$w_origin};
                next unless defined $entry;
                my ($waiting_item, $waiting_alt_idx) = $entry->@*;

                # Advance the waiting item
                my $new_value = $semiring->multiply($waiting_item->{value}, $completed_item->{value});

                # Skip if multiply produced zero — don't propagate rejected
                # completions (e.g. keyword-as-Identifier) to parent items
                next if $semiring->is_zero($new_value);

                my $new_item = $self->_advance_item($waiting_item, $new_value);

                my $new_core_id = $new_item->{core_id};
                my $new_origin  = $new_item->{origin};

                if ($self->_chart_has($chart, $pos, $new_core_id, $new_origin)) {
                    # Merge with existing item using semiring add (create new item, don't mutate)
                    my $existing = $self->_chart_get($chart, $pos, $new_core_id, $new_origin)->[0];
                    my $merged_value;
                    try {
                        $merged_value = $semiring->add($existing->{value}, $new_item->{value});
                    } catch ($e) {
                        my $rn     = $existing->{rule}->name();
                        my $dot    = $existing->{dot};
                        my $e_orig = $existing->{origin};
                        die "Ambiguity in rule '$rn' (dot=$dot, origin=$e_orig, pos=$pos) "
                            . "completing='$rule_name' (origin=$origin): $e";
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
