# ABOUTME: Scanless Earley parser with Predict/Scan/Complete operations.
# ABOUTME: Takes grammar and semiring, returns boolean acceptance for input strings.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Terminal;
use Chalk::Bootstrap::CoreItemIndex;
use Chalk::Bootstrap::LR0DFA;
use Chalk::Bootstrap::Context;

class Chalk::Bootstrap::Earley {
    # Ruby Slippers: the set of terminal patterns that are closing delimiters
    # or semicolons, eligible for virtual insertion during error recovery.
    my %CLOSER_PATTERNS = map { $_ => 1 }
        '\\)', '\\]', '\\}', '\\;', ')', ']', '}', ';';

    field $grammar  :param :reader;
    field $semiring :param :reader;
    field $_recover :param(recover) = false;

    # Leo optimization enable flag. Always true in production; can be
    # overridden to false via the leo_enabled constructor parameter for
    # tests (graph-equivalence harness, etc.) that need to compare Leo-on
    # and Leo-off parses of the same input. Leo is structurally correct
    # for all semirings (proven by t/bootstrap/leo-graph-equivalence.t);
    # the override exists solely to run the comparison.
    field $_leo_enabled :param(leo_enabled) = true;

    # Source file path for diagnostics (set per parse_value call)
    field $_parse_file;
    field $_last_active_pos;
    field $_diag_expected;

    # Error recovery state (parse-lifetime)
    field @_errors;

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

    # GC index: {origin}{rule_name} = 1 — present whenever a {rule}{origin}{*}
    # entry exists in %completed_at. Keyed by origin first so the safe-set GC
    # can walk only the rules that wrote entries at the freed origin, instead
    # of iterating all keys of %completed_at on every freed position. Without
    # this, the GC sweep is O(freed_positions × rules × origins_ever_seen),
    # turning an O(N) parse into O(N²) wall-time.
    field %completed_at_origin_rules;

    # Sparse rd-list per chart cell: $_chart_rd_list[$pos][$cid] is an arrayref
    # of rel_dists that have a defined value at $chart[$pos][$cid][$rd]. Used
    # by chart-walk sites to iterate only populated rds instead of scanning
    # `0 .. $oh->$#*`, which is O(pos - origin) on left-recursive lists where
    # only one rd is actually populated. Writes go through _chart_set.
    field @_chart_rd_list;

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


    # Scan result cache: {pos}{pattern_string} => $end_pos (or undef)
    # Avoids redundant regex matching when multiple items scan the same
    # terminal at the same position (28% of scans are duplicates, 93% fail).
    field %_scan_cache;

    # Compiled regex cache: pattern_string => qr// object
    field %regex_cache;

    # GC statistics for the most recent parse
    field %_gc_stats;

    # Scan statistics for terminal clustering
    field %_scan_stats;


    # Detailed parse profiling (parse-lifetime, only populated when EARLEY_PROFILE is set)
    field %_profile_data;

    # Chart-size snapshot (per-position cell count + non-empty rel_dist count).
    # Populated only when CHALK_CHART_PROFILE is set; cleared per parse.
    field @_chart_snapshot;

    # CoreItemIndex array caches — precomputed at construction time, used in
    # hot loops to bypass method-dispatch overhead on every core_id lookup.
    # Each is a direct reference to the corresponding $core_index getter result.
    field $_ci_completions;
    field $_ci_symbols_after;
    field $_ci_rule_names;
    field $_ci_alt_idxs;

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

        # Cache CoreItemIndex arrays for direct array access in hot loops.
        $_ci_completions   = $core_index->completions();
        $_ci_symbols_after = $core_index->symbols_after();
        $_ci_rule_names    = $core_index->rule_names();
        $_ci_alt_idxs      = $core_index->alt_idxs();
    }

    # Precomputed lookup: nonterminal name => arrayref of core item IDs where
    # the dot is immediately before that nonterminal.
    method waiting_core_ids() { return \%_waiting_core_ids; }

    # GC statistics accessor
    method gc_stats() {
        return \%_gc_stats;
    }

    # Core set registry and DFA table accessors (grammar-lifetime)
    method lr0_dfa() { return $lr0_dfa; }


    # Reset parse-lifetime state (chart, completed_at, leo_items, scan_cache),
    method reset_parse_state() {
        %completed_at = ();
        %completed_at_origin_rules = ();
        @_chart_rd_list = ();
        %leo_items = ();
        %_scan_cache = ();
        %_gc_stats = ();
        $_last_active_pos = 0;
        $_diag_expected = {};
        %_scan_stats = ();
        %_profile_data = ();
        @_errors = ();
    }

    method profile_data() { return \%_profile_data; }

    method chart_snapshot() { return \@_chart_snapshot; }

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
        my $final_count = 0;
        my %final_last_symbols;

        # Pass 1: collect final items and their last symbols
        my $slot = $chart->[$pos];
        # Use cached CoreItemIndex arrays for direct lookup (no method dispatch).
        my $ci_completions   = $_ci_completions;
        my $ci_rule_names    = $_ci_rule_names;
        my $ci_alt_idxs      = $_ci_alt_idxs;
        for my $core_id (0 .. $slot->$#*) {
            my $oh = $slot->[$core_id];
            next unless defined $oh;
            next unless $ci_completions->[$core_id];

            my $rule_name = $ci_rule_names->[$core_id];
            my $alt_idx   = $ci_alt_idxs->[$core_id];
            my $rule = $rule_table->{$rule_name};
            my $rhs = $rule->expressions()->[$alt_idx];

            for my $rd (0 .. $oh->$#*) {
                next unless defined $oh->[$rd];
                # Property 3: reject empty-rule completions
                return false if scalar($rhs->@*) == 0;

                $final_count++;
                $final_last_symbols{$rhs->[-1]->value()} = 1 if $rhs->@*;
            }
        }

        # Property 1: must have at least one final item
        return false unless $final_count;

        if ($ENV{EARLEY_SAFE_DEBUG}) {
            warn sprintf("SAFE_SET_TRACE pos=%d final_count=%d last_syms=%s\n",
                $pos, $final_count, join(',', sort keys %final_last_symbols));
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
        my $ci_symbols_after = $_ci_symbols_after;
        for my $core_id (0 .. $slot->$#*) {
            my $oh = $slot->[$core_id];
            next unless defined $oh;
            next if $ci_completions->[$core_id];

            my $sym = $ci_symbols_after->[$core_id];
            next unless defined $sym;

            if (exists $final_last_symbols{$sym->value()}) {
                if ($ENV{EARLEY_SAFE_DEBUG}) {
                    warn sprintf("SAFE_SET_TRACE pos=%d Property2_fail rule=%s dot=%d sym_after_dot=%s\n",
                        $pos, $core_index->rule_name_for($core_id),
                        $core_index->dot_for($core_id), $sym->value());
                }
                return false;
            }
        }

        if ($ENV{EARLEY_SAFE_DEBUG}) {
            warn sprintf("SAFE_SET pos=%d finals=%d\n", $pos, $final_count);
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
                for my $rd (0 .. $oh->$#*) {
                    next unless defined $oh->[$rd];
                    my $o = $pos - $rd;
                    $min_origin = $o if $o < $min_origin;
                }
            }
            $origin_at_pos{$pos} = $min_origin;
        }
        return \%origin_at_pos;
    }

    # Chart access helpers. Chart structure: $chart[$pos][$core_id][$rel_dist] = $value
    # Origin dimension uses relative distances: rel_dist = pos - origin.
    # Values are stored directly — no item hashref wrappers.
    method _chart_has($chart, $pos, $core_id, $origin) {
        my $oh = $chart->[$pos][$core_id];
        return defined $oh && defined $oh->[($pos - $origin)];
    }

    method _chart_get($chart, $pos, $core_id, $origin) {
        return $chart->[$pos][$core_id][($pos - $origin)];
    }

    method _chart_set($chart, $pos, $core_id, $origin, $value) {
        my $rd = $pos - $origin;
        my $cell = ($chart->[$pos][$core_id] //= []);
        my $was_defined = defined $cell->[$rd];
        $cell->[$rd] = $value;
        # Mirror new rd into the sparse rd-list so iteration sites can walk
        # only populated rds. Overwrites (rd already defined) skip the push.
        if (!$was_defined) {
            push +($_chart_rd_list[$pos][$core_id] //= [])->@*, $rd;
        }
    }

    # Report the chart origin dimension type (for testing)
    method chart_origin_type() { return 'ARRAY'; }

    # Accessor for scan statistics
    method scan_stats() { return \%_scan_stats; }

    # Accessor for errors collected during recovery
    method errors() { return \@_errors; }

    # Find a synchronization point for error recovery (Section 8.3 Tier 2).
    # Scans forward from $start_pos with brace-depth tracking.
    # Returns ($sync_pos, $sync_type) or (undef, undef) if no sync found.
    # sync_type: 'semicolon', 'block_close', 'keyword'
    method _find_sync_point($input, $start_pos) {
        my $n = length($input);
        my $depth = 0;
        my $pos = $start_pos;

        while ($pos < $n) {
            my $ch = substr($input, $pos, 1);

            if ($ch eq '{') {
                $depth++;
            } elsif ($ch eq '}') {
                $depth--;
                if ($depth < 0) {
                    # Closing brace exits the enclosing block
                    return ($pos + 1, 'block_close');
                }
            } elsif ($ch eq ';' && $depth == 0) {
                return ($pos + 1, 'semicolon');
            }

            # Check for declaration keywords at depth 0
            if ($depth == 0 && $ch =~ /[a-z]/) {
                for my $kw (qw(method field class sub use)) {
                    my $kw_len = length($kw);
                    if ($pos + $kw_len <= $n
                        && substr($input, $pos, $kw_len) eq $kw
                        && ($pos + $kw_len >= $n
                            || substr($input, $pos + $kw_len, 1) =~ /\W/))
                    {
                        # Only sync on keyword if it's not at the very start
                        # of the scan (that would be the error position itself)
                        if ($pos > $start_pos) {
                            return ($pos, 'keyword');
                        }
                    }
                }
            }

            $pos++;
        }

        return (undef, undef);
    }

    # Get the symbol after the dot for a core item (O(1) precomputed lookup)
    method _symbol_after_dot_for($core_id) {
        return $core_index->symbol_after($core_id);
    }

    # Check if a core item is complete (O(1) precomputed lookup)
    method _is_complete_id($core_id) {
        return $core_index->is_complete($core_id);
    }

    # Internal parse implementation that returns raw semiring value or undef
    method _run_parse($input) {
        my $n = length($input);

        # Chart: $chart[$pos][$core_id][$rel_dist] = $value
        # where rel_dist = pos - origin. Values are stored directly — no item hashref wrappers.
        # core_id encodes (rule_name, alt_idx, dot); CoreItemIndex provides O(1) lookups.
        my @chart = map { [] } (0 .. $n);

        # Cache CoreItemIndex arrays for hot-loop direct indexing
        # (avoids per-element method dispatch overhead)
        my $ci_completions   = $core_index->completions();
        my $ci_symbols_after = $core_index->symbols_after();
        my $ci_rule_names    = $core_index->rule_names();
        my $ci_alt_idxs      = $core_index->alt_idxs();
        my $ci_states_bulk   = $core_index->states_for_bulk();

        # Reset secondary indexes for this parse
        %completed_at = ();
        %completed_at_origin_rules = ();
        @_chart_rd_list = ();
        %leo_items = ();
        %_scan_cache = ();
        %_gc_stats = (positions_freed => 0, safe_sets_found => 0);
        %_scan_stats = (total_matches => 0, cache_hits => 0, clustered_scans => 0);
        %_profile_data = ();
        @_chart_snapshot = ();
        $_last_active_pos = 0;
        $_diag_expected = {};
        @_errors = ();

        # Find the start rule (first rule in grammar).
        # Convention: grammar->[0] is the start rule (same as LR0DFA.pm).
        my $start_rule = $grammar->[0];

        # Initialize chart[0] with start rule items (one per alternative)
        # rel_dist = 0 - 0 = 0 (origin and pos are both 0)
        for my $alt_idx (0 .. $start_rule->expressions()->$#*) {
            my $core_id = $core_index->id_for($start_rule->name(), $alt_idx, 0);
            $self->_chart_set(\@chart, 0, $core_id, 0, $semiring->one());
        }

        # GC tracking
        my $oldest_live_pos = 0;
        my $last_safe_pos = -1;  # Aycock safe-set tracking

        # Epoch GC: callback for statement-boundary sweeping
        my @pending_sweeps;
        my $on_epoch_commit = sub ($origin, $end) {
            push @pending_sweeps, [$origin, $end];
        };

        # Track the furthest chart position that has entries (from scanning).
        # Multi-character terminal scans can jump from pos P to pos P+N,
        # leaving intermediate positions empty. Stall detection should only
        # trigger when we're past this frontier, not at skipped positions.
        my $furthest_chart_pos = 0;

        # Process each chart position (while loop enables recovery skip)
        my $pos = 0;
        while ($pos <= $n) {
            # Build agenda from all entries at this position.
            # Agenda carries [$core_id, $origin] pairs; values are in the chart.
            # Chart uses relative distances: rel_dist = pos - origin.
            my @agenda;
            my @active_cids;  # core_ids with at least one defined value
            for my $core_id (0 .. $chart[$pos]->$#*) {
                my $oh = $chart[$pos][$core_id];
                next unless defined $oh;
                my $found = false;
                for my $rel_dist (0 .. $oh->$#*) {
                    next unless defined $oh->[$rel_dist];
                    push @agenda, [$core_id, $pos - $rel_dist];
                    $found = true;
                }
                push @active_cids, $core_id if $found;
            }

            # Stall detection: empty agenda means no items survived to this
            # position. If recovery is enabled, try Ruby Slippers (virtual
            # delimiter insertion) first, then fall back to panic mode.
            # Only trigger when past the scanner frontier — empty positions
            # within the frontier are normal (multi-char terminals skip them).
            if (!@agenda && $pos > $furthest_chart_pos && $pos <= $n && $_recover) {
                if (scalar(@_errors) < 20) {
                    # Tier 1: Ruby Slippers — try inserting expected closing delimiters.
                    # Check if expected tokens include a delimiter that would let
                    # parsing continue. Insert it as a zero-width virtual token.
                    my $ruby_recovered = false;
                    if ($_diag_expected && $_diag_expected->%*) {
                        my @closers = grep { exists $CLOSER_PATTERNS{$_} }
                                      keys $_diag_expected->%*;
                        for my $closer (@closers) {
                            # Find items at the last active position waiting for this terminal
                            my $prev_pos = $_last_active_pos;
                            next unless defined $prev_pos;
                            for my $cid (0 .. $chart[$prev_pos]->$#*) {
                                my $oh = $chart[$prev_pos][$cid];
                                next unless defined $oh;
                                next if $self->_is_complete_id($cid);
                                my $sym = $self->_symbol_after_dot_for($cid);
                                next unless defined $sym && !$sym->is_reference();
                                next unless $sym->value() eq $closer;
                                # This item expects the closer — virtually scan it
                                for my $rd (0 .. $oh->$#*) {
                                    next unless defined $oh->[$rd];
                                    my $item_origin = $prev_pos - $rd;
                                    my $val = $oh->[$rd];
                                    # Advance the item as if the closer was scanned (empty text)
                                    my $vscan_ctx = $self->_make_scan_context(
                                        '', $core_index->rule_name_for($cid),
                                        $core_index->alt_idx_for($cid), {});
                                    my $new_value = $semiring->multiply($val, $vscan_ctx);
                                    next if $semiring->is_zero($new_value);
                                    my $new_cid = $core_index->advance($cid);
                                    # Place at current position (zero-width insertion)
                                    $self->_chart_set(\@chart, $pos, $new_cid, $item_origin, $new_value);
                                    $ruby_recovered = true;
                                }
                            }
                        }
                    }
                    if ($ruby_recovered) {
                        push @_errors, {
                            position      => $pos,
                            expected      => { $_diag_expected->%* },
                            recovery_type => 'ruby_slippers',
                        };
                        # Re-build agenda from newly inserted items and continue
                        next;
                    }

                    # Tier 2: panic mode — scan forward to sync point
                    if ($pos < $n) {
                        push @_errors, {
                            position  => $pos,
                            expected  => { $_diag_expected->%* },
                        };

                        my ($sync_pos, $sync_type) = $self->_find_sync_point($input, $pos);
                        if (defined $sync_pos) {
                            $_errors[-1]{sync_pos}  = $sync_pos;
                            $_errors[-1]{sync_type} = $sync_type;

                            # Seed chart at recovery position with start rule items
                            for my $alt_idx (0 .. $start_rule->expressions()->$#*) {
                                my $seed_id = $core_index->id_for(
                                    $start_rule->name(), $alt_idx, 0);
                                $self->_chart_set(\@chart, $sync_pos, $seed_id, $sync_pos, $semiring->one());
                            }
                            $pos = $sync_pos;
                            next;
                        }
                    }
                }
                # No recovery succeeded or error limit reached — stop
                last;
            }

            # Track furthest position with active items for diagnostics
            if (@agenda) {
                $_last_active_pos = $pos;
                $furthest_chart_pos = $pos if $pos > $furthest_chart_pos;
            }

            my @processed;
            my %predicted_at;  # Track which rules have been predicted at this pos

            # Pre-predict nonterminals and pre-scan terminals in a single pass
            # over active core_ids. The @active_cids list was built during agenda
            # construction, avoiding a redundant has_values scan per item.
            if ($pos < $n) {
                my %seen_patterns;
                my %seen_states;
                for my $cid (@active_cids) {
                    # Prediction: if this item expects a nonterminal, predict it
                    if (!$ci_completions->[$cid]) {
                        my $sym = $ci_symbols_after->[$cid];
                        if (defined $sym && $sym->is_reference()) {
                            $self->_predict($sym->value(), $pos, \@chart, \@agenda, \%predicted_at);
                        }
                    }

                    # Terminal clustering: look up DFA state and union its
                    # terminal_map patterns into the scan cache. Each distinct
                    # pattern is tried once per position.
                    my $state_id = $ci_states_bulk->[$cid];
                    next unless defined $state_id;
                    next if $seen_states{$state_id}++;

                    my $tmap = $lr0_dfa->state($state_id)->{terminal_map};
                    for my $pstr (keys $tmap->%*) {
                        next if $seen_patterns{$pstr}++;
                        next if exists $_scan_cache{$pos} && exists $_scan_cache{$pos}{$pstr};
                        my $pattern = $regex_cache{$pstr} //= qr/$pstr/;
                        $_scan_cache{$pos}{$pstr} = Chalk::Bootstrap::Terminal::match($input, $pos, $pattern);
                        $_scan_stats{clustered_scans}++;
                    }
                }
            }

            while (my $entry = shift @agenda) {
                my ($core_id, $origin) = $entry->@*;

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

                # Read value from chart (may have been updated by a merge since
                # this entry was pushed to the agenda)
                my $value = $chart[$pos][$core_id][($pos - $origin)];

                if ($ci_completions->[$core_id]) {
                    # Apply completion reification via multiply: build an annotated
                    # Context carrying rule metadata, then multiply the accumulated
                    # value by it. Each semiring detects annotations->{complete}=true
                    # in its multiply and applies its rule-completion logic.
                    my $rule_name = $ci_rule_names->[$core_id];
                    my $alt_idx = $ci_alt_idxs->[$core_id];
                    my $complete_ctx = $self->_make_complete_context(
                        $value, $rule_name, $alt_idx, $pos, $origin
                    );
                    my $completed_value = $semiring->multiply($value, $complete_ctx);
                    # Update the chart entry with the reification-applied value
                    $self->_chart_set(\@chart, $pos, $core_id, $origin, $completed_value);
                    # Skip propagation of zero-valued completions. A zero
                    # from multiply (e.g. TypeInference rejecting a
                    # keyword-as-Identifier) must not poison parent items
                    # via multiply — the valid parse path will supply
                    # the correct value independently.
                    next if !defined($completed_value) || $semiring->is_zero($completed_value);
                    # Epoch boundary: StatementItem completion signals parse-position GC.
                    # Fired here (after reification) rather than inside SA.multiply to
                    # keep the epoch mechanism decoupled from semiring internals.
                    if (defined $on_epoch_commit && $rule_name eq 'StatementItem') {
                        $on_epoch_commit->($origin, $pos);
                    }
                    # Index this completed item for _advance_from_completed lookups.
                    # Only non-zero completions are indexed — zero-valued entries
                    # would cause wasted work in _advance_from_completed.
                    $completed_at{$rule_name}{$origin}{$pos} //= [];
                    push $completed_at{$rule_name}{$origin}{$pos}->@*, [$core_id, $origin];
                    $completed_at_origin_rules{$origin}{$rule_name} = 1;
                    # Complete
                    $self->_complete($core_id, $origin, $completed_value, $pos, \@chart, \@agenda);
                } else {
                    my $symbol = $ci_symbols_after->[$core_id];
                    my $rule_name = $ci_rule_names->[$core_id];
                    my $alt_idx = $ci_alt_idxs->[$core_id];

                    if ($symbol->is_reference()) {
                        my $w_rule = $symbol->value();

                        # Inline ? handling: create skip path that advances
                        # past the optional symbol without matching it.
                        # DFA prediction handles this for initially-predicted
                        # items (dot=0 advancement); this handles mid-rule
                        # optionals where the dot reaches B? during parsing.
                        if ($symbol->is_quantified() && $symbol->quantifier() eq '?') {
                            my $skip_value = $semiring->multiply($value, $semiring->one());
                            my $skip_is_zero = defined $skip_value ? $semiring->is_zero($skip_value) : true;
                            if (defined $skip_value && !$skip_is_zero) {
                                my $skip_core = $core_index->advance($core_id);
                                my $skip_rd = $pos - $origin;
                                my $skip_oh = $chart[$pos][$skip_core];
                                if (defined $skip_oh && defined $skip_oh->[$skip_rd]) {
                                    my $existing_val = $skip_oh->[$skip_rd];
                                    my $merged;
                                    try {
                                        $merged = $semiring->add(
                                            $existing_val, $skip_value
                                        );
                                    } catch ($e) {
                                        my $rn = $core_index->rule_name_for($skip_core);
                                        die "Ambiguity in skip-optional merge for '$rn' "
                                            . "(pos=$pos, origin=$origin): $e";
                                    }
                                    my $merged_is_zero = $semiring->is_zero($merged);
                                    if (!$merged_is_zero) {
                                        $self->_chart_set(\@chart, $pos, $skip_core, $origin, $merged);
                                        my $sp_slot = $processed[$skip_core];
                                        my $sp_done = defined $sp_slot && $sp_slot->[$origin];
                                        push @agenda, [$skip_core, $origin]
                                            unless $sp_done;
                                    }
                                } else {
                                    $self->_chart_set(\@chart, $pos, $skip_core, $origin, $skip_value);
                                    push @agenda, [$skip_core, $origin];
                                }
                            }
                        }

                        # Predict
                        # Lateral-seed channel: when a StatementList item
                        # predicts StatementItem, seed the prediction with the
                        # preceding statement's control_head so the next
                        # statement's action sees the correct predecessor.
                        my $lateral_seed = undef;
                        if ($w_rule eq 'StatementItem'
                                && $rule_name eq 'StatementList'
                                && blessed($value) && $value->can('control_head')) {
                            my $ch = $value->control_head();
                            if (defined $ch && $ch->can('operation')
                                    && $ch->operation ne 'Start') {
                                $lateral_seed = $ch;
                            }
                        }
                        $self->_predict($w_rule, $pos, \@chart, \@agenda, \%predicted_at, $lateral_seed);
                        # Advance from already-completed items at this position.
                        # When a nullable nonterminal (e.g. _) appears multiple
                        # times in a rule, the second prediction is suppressed
                        # (already predicted). The completion that ran earlier
                        # couldn't advance this waiting item because it didn't
                        # exist yet. So we check for completed items now.
                        $self->_advance_from_completed(
                            $core_id, $origin, $value, $symbol, $pos, \@chart, \@agenda
                        );
                    } else {
                        # Scan (allow at end of input for zero-width matches)
                        $self->_scan($core_id, $origin, $value, $symbol, $pos, $input, \@chart, $n, \@agenda, \%predicted_at);
                    }
                }
            }

            # Update scan frontier: check scan cache for this position to find
            # the furthest position that scanning advanced items to.
            if (exists $_scan_cache{$pos}) {
                for my $end (values $_scan_cache{$pos}->%*) {
                    $furthest_chart_pos = $end
                        if defined $end && $end > $furthest_chart_pos;
                }
            }

            # Snapshot expected tokens after full agenda processing.
            # At this point all predictions have been added so the chart
            # contains items waiting for their next symbol — exactly the
            # set of tokens that would allow parsing to continue.
            if ($pos == $_last_active_pos) {
                $_diag_expected = {};
                for my $core_id (0 .. $chart[$pos]->$#*) {
                    my $oh = $chart[$pos][$core_id];
                    next unless defined $oh && $oh->@*;
                    next if $self->_is_complete_id($core_id);
                    my $sym = $self->_symbol_after_dot_for($core_id);
                    if (defined $sym && !$sym->is_reference()) {
                        $_diag_expected->{$sym->value()} = 1;
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
                    # Also preserve items whose origin equals sweep_origin:
                    # these are boundary items (e.g. IfStatement waiting for
                    # ElsifChain?) that may still be needed by completions
                    # arriving after this sweep. Only sweep items whose
                    # origin is strictly inside the epoch.
                    for my $sp ($sweep_origin + 1 .. $sweep_end - 1) {
                        next if $sp >= $pos;  # don't sweep current position
                        my $slot = $chart[$sp];
                        next unless defined $slot && $slot->@*;
                        # max_rd: items with origin > sweep_origin have
                        # rel_dist < sp - sweep_origin
                        my $max_rd = $sp - $sweep_origin;
                        for my $cid (0 .. $slot->$#*) {
                            my $oh = $slot->[$cid];
                            next unless defined $oh;
                            next unless $self->_is_complete_id($cid);
                            my $rd_list = $_chart_rd_list[$sp][$cid];
                            for my $rd (0 .. $oh->$#*) {
                                next unless $rd < $max_rd;
                                next unless defined $oh->[$rd];
                                # Only null completed items — incomplete items
                                # may still be needed by future completions
                                # (e.g. ElsifChain waiting for recursive child)
                                $oh->[$rd] = undef;
                            }
                            # Rebuild the rd-list for this cell from defined
                            # entries, since epoch sweep can null arbitrary
                            # rds. Only run when the list exists (it always
                            # should, since values were written via _chart_set).
                            if (defined $rd_list) {
                                $_chart_rd_list[$sp][$cid] = [
                                    grep { defined $oh->[$_] } $rd_list->@*
                                ];
                            }
                        }
                    }
                    # Phase 2: compact positions where all values are null
                    for my $sp ($sweep_origin + 1 .. $sweep_end - 1) {
                        next if $sp >= $pos;
                        my $slot = $chart[$sp];
                        next unless defined $slot && $slot->@*;
                        my $all_null = true;
                        for my $oh ($slot->@*) {
                            last unless $all_null;
                            next unless defined $oh;
                            for my $val ($oh->@*) {
                                if (defined $val) {
                                    $all_null = false;
                                    last;
                                }
                            }
                        }
                        if ($all_null) {
                            $chart[$sp] = [];
                            $_chart_rd_list[$sp] = undef;
                            delete $_scan_cache{$sp};
                            $_gc_stats{positions_freed}++;
                        }
                    }
                }
                @pending_sweeps = ();
            }

            # Aycock safe-set GC: if this position is a safe set, free
            # all chart positions between the previous safe set and this one.
            # The safe-set properties (Aycock Ch6) guarantee that all items
            # originating inside the window have already completed and their
            # results have been propagated to the boundary positions. No
            # future _complete call will need to look up chart[origin] for
            # an origin inside the freed window.
            if ($self->_is_safe_set(\@chart, $pos)) {
                if ($last_safe_pos >= 0 && $pos > $last_safe_pos + 1) {
                    # Verify no open item at pos has an origin inside
                    # the candidate window. If one does, freeing that
                    # origin position would break _complete lookups.
                    my $safe_to_free = true;
                    for my $cid (0 .. $chart[$pos]->$#*) {
                        last unless $safe_to_free;
                        my $oh = $chart[$pos][$cid];
                        next unless defined $oh;
                        # Complete items are safe to free — only incomplete
                        # items with origins in the window block freeing
                        next if $self->_is_complete_id($cid);
                        # Check if any origin is in (last_safe_pos, pos)
                        # rel_dist = pos - origin, so origin in that range
                        # means rel_dist in (0, pos - last_safe_pos)
                        my $min_rd = 1;  # origin < pos → rd > 0
                        my $max_rd = $pos - $last_safe_pos;  # origin > last_safe_pos
                        for my $rd ($min_rd .. $max_rd - 1) {
                            if (defined $oh->[$rd]) {
                                $safe_to_free = false;
                                last;
                            }
                        }
                    }
                    if ($safe_to_free) {
                        for my $sp ($last_safe_pos + 1 .. $pos - 1) {
                            if (defined $chart[$sp] && $chart[$sp]->@*) {
                                $chart[$sp] = [];
                                $_chart_rd_list[$sp] = undef;
                                delete $_scan_cache{$sp};
                                $_gc_stats{positions_freed}++;
                            }
                            # Drop the origin=$sp branch for every rule that
                            # wrote at that origin. The %completed_at_origin_rules
                            # index lets us touch only populated (rule, origin)
                            # pairs instead of walking all rules × all origins.
                            #
                            # Entries with chart_pos=$sp under {rule}{origin<sp}
                            # are unreachable (reads use {pos}{pos} where
                            # pos==origin) and are left in place; the per-parse
                            # reset_parse_state at the start of the next parse
                            # reclaims them. Adding a chart_pos index here would
                            # restore their cleanup at the cost of an extra
                            # write per completion.
                            if (my $rules = delete $completed_at_origin_rules{$sp}) {
                                for my $rule_name (keys %$rules) {
                                    delete $completed_at{$rule_name}{$sp};
                                }
                            }
                        }
                        $oldest_live_pos = $last_safe_pos
                            if $last_safe_pos > $oldest_live_pos;
                    }
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
                        for my $rd (0 .. $oh->$#*) {
                            next unless defined $oh->[$rd];
                            my $o = $q - $rd;
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
                    $items_at_pos += scalar grep { defined } $oh->@*;
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
                        while (defined(my $line = readline($sf))) { $rss = $1 if $line =~ /VmRSS:\s+(\d+)/ }
                        close $sf;
                    }
                    warn sprintf("PROFILE pos=%d items_here=%d total=%d max=%d live_span=%d rss=%dkB\n",
                        $pos, $items_at_pos, $_profile_data{total_items},
                        $_profile_data{max_items_at_pos}, $_profile_data{live_positions}, $rss);
                }
            }

            $pos++;
        }

        if ($ENV{CHALK_CHART_PROFILE}) {
            for my $p (0 .. $#chart) {
                my $row = $chart[$p];
                my $cells = 0;
                my $entries = 0;
                if (defined $row) {
                    for my $cid (0 .. $row->$#*) {
                        my $oh = $row->[$cid];
                        next unless defined $oh;
                        $cells++;
                        for my $rd (0 .. $oh->$#*) {
                            $entries++ if defined $oh->[$rd];
                        }
                    }
                }
                $_chart_snapshot[$p] = { cells => $cells, entries => $entries };
            }
        }

        # Check if we have a completed start rule spanning entire input
        for my $alt_idx (0 .. $start_rule->expressions()->$#*) {
            my $end_dot = scalar($start_rule->expressions()->[$alt_idx]->@*);
            my $core_id = $core_index->id_for($start_rule->name(), $alt_idx, $end_dot);

            my $end_oh = $chart[$n][$core_id];
            if (defined $end_oh && defined $end_oh->[$n]) {
                return $end_oh->[$n];
            }
        }

        # Ruby Slippers at EOF: if the parse ended without a completed start rule
        # and recovery is enabled, try inserting virtual closing delimiters.
        # Repeat until no more insertions are possible or the start rule completes.
        if ($_recover && scalar(@_errors) < 20) {
            my $max_ruby_rounds = 10;  # prevent infinite loops
            for my $round (1 .. $max_ruby_rounds) {
                my $inserted = false;
                # Find items at $n waiting for closing delimiters
                for my $cid (0 .. $chart[$n]->$#*) {
                    my $oh = $chart[$n][$cid];
                    next unless defined $oh;
                    next if $self->_is_complete_id($cid);
                    my $sym = $self->_symbol_after_dot_for($cid);
                    next unless defined $sym && !$sym->is_reference();
                    my $pat = $sym->value();
                    # Only insert closing delimiters and semicolons
                    next unless exists $CLOSER_PATTERNS{$pat};
                    for my $rd (0 .. $oh->$#*) {
                        next unless defined $oh->[$rd];
                        my $item_origin = $n - $rd;
                        my $val = $oh->[$rd];
                        my $vscan_ctx = $self->_make_scan_context(
                            '', $core_index->rule_name_for($cid),
                            $core_index->alt_idx_for($cid), {});
                        my $new_value = $semiring->multiply($val, $vscan_ctx);
                        next if $semiring->is_zero($new_value);
                        my $new_cid = $core_index->advance($cid);
                        # Place at $n (zero-width virtual token)
                        if ($self->_chart_has(\@chart, $n, $new_cid, $item_origin)) {
                            my $existing = $self->_chart_get(\@chart, $n, $new_cid, $item_origin);
                            my $merged = $semiring->add($existing, $new_value);
                            $self->_chart_set(\@chart, $n, $new_cid, $item_origin, $merged);
                        } else {
                            $self->_chart_set(\@chart, $n, $new_cid, $item_origin, $new_value);
                        }
                        $inserted = true;
                    }
                }
                last unless $inserted;

                # Process completions from virtual insertions.
                # Pass a real arrayref (not undef) so _complete can push
                # newly discovered items for further processing.
                my @virt_agenda;
                for my $cid (0 .. $chart[$n]->$#*) {
                    next unless $self->_is_complete_id($cid);
                    my $oh = $chart[$n][$cid];
                    next unless defined $oh;
                    for my $rd (0 .. $oh->$#*) {
                        next unless defined $oh->[$rd];
                        push @virt_agenda, [$cid, $n - $rd];
                    }
                }
                my @virt_new;
                for my $entry (@virt_agenda) {
                    my ($cid, $origin) = $entry->@*;
                    $self->_complete(
                        $cid, $origin, $chart[$n][$cid][($n - $origin)],
                        $n, \@chart, \@virt_new,
                    );
                }

                push @_errors, {
                    position      => $n,
                    expected      => { $_diag_expected->%* },
                    recovery_type => 'ruby_slippers',
                    round         => $round,
                };

                # Check if start rule now completes
                for my $alt_idx (0 .. $start_rule->expressions()->$#*) {
                    my $end_dot = scalar($start_rule->expressions()->[$alt_idx]->@*);
                    my $check_id = $core_index->id_for($start_rule->name(), $alt_idx, $end_dot);
                    my $check_oh = $chart[$n][$check_id];
                    if (defined $check_oh && defined $check_oh->[$n]) {
                        return $check_oh->[$n];
                    }
                }
            }
        }

        # With recovery enabled, the start rule may not span the full input
        # (origin 0 to $n) because recovery seeds fresh start-rule items at
        # the sync position. Check for a start rule completion from any origin.
        if ($_recover && @_errors) {
            for my $alt_idx (0 .. $start_rule->expressions()->$#*) {
                my $end_dot = scalar($start_rule->expressions()->[$alt_idx]->@*);
                my $core_id = $core_index->id_for($start_rule->name(), $alt_idx, $end_dot);

                my $end_oh = $chart[$n][$core_id];
                next unless defined $end_oh;
                for my $rd (0 .. $end_oh->$#*) {
                    next unless defined $end_oh->[$rd];
                    # Found a completed start rule from a recovery origin
                    return $end_oh->[$rd];
                }
            }
        }

        return;
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
        # Phase 4 stopgap: if the final result is packed-ambiguous, the
        # filter stack admitted multiple derivations none of which were
        # disambiguated by Phase 1-4. Pick the first survivor. Phase 5
        # will replace this with structured Program-rule resolution.
        if (defined $result
                && $result->can('is_ambiguous')
                && $result->is_ambiguous()) {
            my $survivors = $result->children();
            $result = $survivors->[0] if $survivors && $survivors->@*;
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
    # lists nullable symbol names (both ?-quantified and epsilon-nullable
    # nonterminals) skipped to reach that dot position
    # (Aycock nullable optimization). For dot>0 items with skipped nullable
    # symbols, absent optionals produce multiply(value, one()) which creates
    # an unfocused Context node for each skipped symbol.
    # Tracks which rules have been predicted at each position to avoid
    # re-iterating the prediction set on redundant calls.
    method _predict($rule_name, $pos, $chart, $agenda, $predicted_at = undef, $control_head = undef) {

        # Skip if this rule was already predicted at this position
        if (defined $predicted_at) {
            return if $predicted_at->{$rule_name};
            $predicted_at->{$rule_name} = true;
        }

        my $prediction_items = $lr0_dfa->prediction_items_for($rule_name);
        return unless defined $prediction_items;

        # When a control_head is provided (lateral-seed channel), use
        # one_with_control to seed the initial value so the next
        # statement's action sees the preceding statement's node as its
        # control predecessor rather than the bare Start seed.
        my $seed_value = defined($control_head)
            ? $semiring->one_with_control($control_head)
            : $semiring->one();

        for my $pred_entry ($prediction_items->@*) {
            my ($core_id, $skip_symbols) = $pred_entry->@*;
            # Inlined _chart_has: rd=0 since origin==pos for predicted items.
            my $existing_oh = $chart->[$pos][$core_id];
            unless (defined $existing_oh && defined $existing_oh->[0]) {
                my $info = $core_index->item_for($core_id);

                # Build initial value. For dot>0 items with skipped nullable symbols,
                # absent optionals produce multiply(value, one()) which creates
                # an unfocused Context node.
                my $value = $seed_value;
                if ($skip_symbols && $skip_symbols->@*) {
                    for my $sym_name ($skip_symbols->@*) {
                        $value = $semiring->multiply($value, $semiring->one());
                        last if !defined $value || $semiring->is_zero($value);
                    }
                    next if !defined $value || $semiring->is_zero($value);
                }

                $self->_chart_set($chart, $pos, $core_id, $pos, $value);
                push $agenda->@*, [$core_id, $pos];
            }
        }
    }

    # Scan: match terminal and advance to next position.
    # Takes core_id, origin, and value directly (no item hashref).
    method _scan($core_id, $origin, $value, $symbol, $pos, $input, $chart, $n, $agenda = undef, $predicted_at = undef) {
        my $pattern_str = $symbol->value();

        # Check scan result cache before attempting regex match.
        # Terminal clustering (inline at the top of the position loop in
        # _run_parse) pre-populates this cache, so most lookups are hits.
        my $end_pos;
        if (exists $_scan_cache{$pos} && exists $_scan_cache{$pos}{$pattern_str}) {
            $end_pos = $_scan_cache{$pos}{$pattern_str};
            $_scan_stats{cache_hits}++;
        } else {
            my $pattern = $regex_cache{$pattern_str} //= qr/$pattern_str/;
            $end_pos = Chalk::Bootstrap::Terminal::match($input, $pos, $pattern);
            $_scan_cache{$pos}{$pattern_str} = $end_pos;
        }
        $_scan_stats{total_matches}++;

        return unless defined $end_pos;

        # Capture matched text
        my $matched = substr($input, $pos, $end_pos - $pos);

        # Build an annotated scan Context carrying matched text and metadata.
        # predicted_at tracks which rules have been predicted at this position,
        # which scan-aware semirings (TypeInference, Precedence) use for
        # keyword rejection and operator validation.
        # Using the caller's hashref avoids iterating field hash keys (which
        # the XS codegen cannot handle).
        my $is_predicted = $predicted_at // {};

        my $rule_name = $core_index->rule_name_for($core_id);
        my $alt_idx = $core_index->alt_idx_for($core_id);

        # Combine existing value with scan via multiply.
        # The scan Context carries matched_text (focus), rule_name, alt_idx,
        # and predicted (the predicted_at hashref) so semirings can inspect
        # scan metadata inline during multiply.
        my $scan_ctx = $self->_make_scan_context($matched, $rule_name, $alt_idx, $is_predicted);
        my $new_value = $semiring->multiply($value, $scan_ctx);

        # multiply returns zero if scan is rejected (semiring filtering)
        return if $semiring->is_zero($new_value);

        # Advance dot
        my $new_core_id = $core_index->advance($core_id);

        if ($self->_chart_has($chart, $end_pos, $new_core_id, $origin)) {
            # Merge with existing value using semiring add
            my $existing_val = $self->_chart_get($chart, $end_pos, $new_core_id, $origin);
            my $merged_value;
            try {
                $merged_value = $semiring->add($existing_val, $new_value);
            } catch ($e) {
                my $rn = $core_index->rule_name_for($new_core_id);
                die "Ambiguity in scan merge for '$rn' "
                    . "(pos=$pos, end_pos=$end_pos, origin=$origin): $e";
            }
            $self->_chart_set($chart, $end_pos, $new_core_id, $origin, $merged_value);
            # If zero-width match, add to current agenda for immediate processing
            if ($end_pos == $pos && $agenda) {
                push $agenda->@*, [$new_core_id, $origin];
            }
        } else {
            $self->_chart_set($chart, $end_pos, $new_core_id, $origin, $new_value);
            # If zero-width match, add to current agenda for immediate processing
            if ($end_pos == $pos && $agenda) {
                push $agenda->@*, [$new_core_id, $origin];
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
    # Takes core_id, origin, and completed_value directly (no item hashref).
    method _complete($completed_core_id, $origin, $completed_value, $pos, $chart, $agenda) {
        my $rule_name = $core_index->rule_name_for($completed_core_id);

        # Leo resolution: check if a Leo item exists for this rule at origin.
        # Leo items are keyed by (rule_name, origin) where origin is where the
        # waiting items live. When a completion has this origin, the Leo item
        # shortcuts the chain by one level. Each Leo item covers exactly one
        # chain level — resolution invokes multiply(leo->value, completed)
        # which matches the non-Leo path's multiply(waiting_value, completed)
        # byte for byte, so Leo-on and Leo-off produce isomorphic Context
        # graphs. The $_leo_enabled flag is always true in production; the
        # test harness at t/bootstrap/leo-graph-equivalence.t uses
        # leo_enabled => 0 to get reference parses without Leo for comparison.
        my $leo_resolved_core_id;
        my $leo_resolved_origin;
        if ($_leo_enabled
            && (my $leo = $leo_items{$rule_name}{$origin})) {
            my $combined = $semiring->multiply($leo->{value}, $completed_value);
            unless ($semiring->is_zero($combined)) {
                my $top_core_id = $leo->{top_core_id};
                my $top_origin  = $leo->{top_origin};
                my $new_core_id = $core_index->advance($top_core_id);

                if ($self->_chart_has($chart, $pos, $new_core_id, $top_origin)) {
                    my $existing_val = $self->_chart_get($chart, $pos, $new_core_id, $top_origin);
                    my $merged_value;
                    try {
                        $merged_value = $semiring->add($existing_val, $combined);
                    } catch ($e) {
                        die "Ambiguity resolving Leo item for '$rule_name' "
                            . "(top_core=$top_core_id, top_origin=$top_origin, pos=$pos): $e";
                    }
                    $self->_chart_set($chart, $pos, $new_core_id, $top_origin, $merged_value);
                } else {
                    $self->_chart_set($chart, $pos, $new_core_id, $top_origin, $combined);
                    push $agenda->@*, [$new_core_id, $top_origin];
                }
            }
            # Track which waiting item the Leo covered so we skip it below.
            # Use the immediate waiting item identity (wait_core_id/wait_origin),
            # not top — after chain extension, top may be at a distant
            # origin that doesn't match the actual waiting item at this position.
            $leo_resolved_core_id = $leo->{wait_core_id};
            $leo_resolved_origin = $leo->{wait_origin};
        }

        # Completion filter (design doc Section 7.5):
        # Layer 1: global_waiting_core_ids — all grammar-wide candidates
        # Layer 2: chart liveness — confirms the waiter has a defined value
        #
        # NOTE: The design doc describes a DFA state completion_map layer
        # between these two, but with the static state_for_core mapping it
        # is a no-op: every waiter's mapped state contains $rule_name in
        # its completion_map by construction. To make DFA narrowing effective,
        # we would need per-position DFA state tracking (the completion_map
        # core_id list would replace _waiting_core_ids as the candidate set).
        my $chart_waiting_ids = $_waiting_core_ids{$rule_name};
        return unless defined $chart_waiting_ids;

        # Count non-zero waiting items and track the single candidate for Leo
        my $eligible_count = 0;
        my $leo_candidate_core_id;
        my $leo_candidate_w_origin;
        my $leo_candidate_value;
        my $leo_candidate_waiting_value;

        for my $w_core_id ($chart_waiting_ids->@*) {
            # Layer 2: chart liveness — confirm waiter is live at origin
            my $oh = $chart->[$origin][$w_core_id];
            next unless defined $oh;

            my $rd_list = $_chart_rd_list[$origin][$w_core_id];
            next unless defined $rd_list && $rd_list->@*;

            for my $w_rd ($rd_list->@*) {
                next unless defined $oh->[$w_rd];
                my $w_origin = $origin - $w_rd;

                # Skip the waiting item already handled by Leo resolution above.
                # Uses explicit if-block because postfix `next if ... &&` miscompiles
                # in XS codegen (garbled eval_pv fallback).
                if (defined $leo_resolved_core_id) {
                    next if $w_core_id == $leo_resolved_core_id
                        && $w_origin  == $leo_resolved_origin;
                }

                my $waiting_value = $oh->[$w_rd];
                # Skip items whose value was nulled by epoch GC — the item's
                # results were already propagated before the sweep.
                next unless defined $waiting_value;

                # Advance the waiting item
                my $new_value = $semiring->multiply($waiting_value, $completed_value);

                # Skip if multiply produced zero — don't propagate rejected
                # completions (e.g. keyword-as-Identifier) to parent items
                next if $semiring->is_zero($new_value);

                my $new_core_id = $core_index->advance($w_core_id);

                my $new_rd = $pos - $w_origin;
                my $existing_oh = $chart->[$pos][$new_core_id];
                my $existing_val = defined($existing_oh) ? $existing_oh->[$new_rd] : undef;
                if (defined $existing_val) {
                    # Merge with existing value using semiring add
                    my $merged_value;
                    try {
                        $merged_value = $semiring->add($existing_val, $new_value);
                    } catch ($e) {
                        my $rn     = $core_index->rule_name_for($new_core_id);
                        my $dot    = $core_index->dot_for($new_core_id);
                        die "Ambiguity in rule '$rn' (dot=$dot, origin=$w_origin, pos=$pos) "
                            . "completing='$rule_name' (origin=$origin): $e";
                    }
                    $self->_chart_set($chart, $pos, $new_core_id, $w_origin, $merged_value);
                } else {
                    $self->_chart_set($chart, $pos, $new_core_id, $w_origin, $new_value);
                    push $agenda->@*, [$new_core_id, $w_origin];
                }

                # Track Leo eligibility: count non-zero waiting items
                $eligible_count++;
                $leo_candidate_core_id = $w_core_id;
                $leo_candidate_w_origin = $w_origin;
                $leo_candidate_value = $new_value;
                $leo_candidate_waiting_value = $waiting_value;
            }
        }

        # Leo creation: if exactly one waiting item produced a non-zero result
        # AND no Leo item was already resolved (deterministic = total 1 waiter),
        # and advancing it would make it complete (penultimate position),
        # create a Leo item keyed at the origin position.
        if ($eligible_count == 1 && !defined $leo_resolved_core_id
            && $_leo_enabled) {
            my $w_dot = $core_index->dot_for($leo_candidate_core_id);
            my $w_alt_idx = $core_index->alt_idx_for($leo_candidate_core_id);
            my $w_rule_name = $core_index->rule_name_for($leo_candidate_core_id);
            my $w_rule = $rule_table->{$w_rule_name};
            my $alt = $w_rule->expressions()->[$w_alt_idx];
            my $advanced_dot = $w_dot + 1;

            # Penultimate check: after advancing, the item would be complete
            if ($advanced_dot >= scalar $alt->@*) {
                # Store Leo item at $origin (where the waiting items live).
                # The value is the raw waiting-item value — NOT its product
                # with the current completion. Leo resolution multiplies
                # stored-value by the new completion, producing exactly what
                # the non-Leo path's multiply(waiting_value, completed_value)
                # would produce. Each Leo item covers one chain level;
                # resolution fires once per link. This keeps Context trees
                # isomorphic between Leo-on and Leo-off parses.
                #
                # Earlier versions also extended parent Leo chains into a
                # single multi-level item. That optimization baked the old
                # completion into the stored value, which made later
                # resolutions produce a tree with extra intermediate nodes.
                # Removed so graph equivalence holds across all semirings.
                #
                # wait_core_id/wait_origin track the immediate waiting item
                # so _complete can skip it.
                $leo_items{$rule_name}{$origin} = {
                    leo          => true,
                    rule_name    => $rule_name,
                    top_origin   => $leo_candidate_w_origin,
                    value        => $leo_candidate_waiting_value,
                    top_core_id  => $leo_candidate_core_id,
                    wait_core_id => $leo_candidate_core_id,
                    wait_origin  => $leo_candidate_w_origin,
                };
            }
        }
    }

    # Create an annotated Context for a scan event.
    # The focus is the matched text; annotations record the scan event metadata
    # so semirings can inspect it during multiply-based reification.
    # position defaults to 0; the caller is responsible for setting it
    # via a subsequent Context construction if a specific position is needed.
    method _make_scan_context($matched_text, $rule_name, $alt_idx, $predicted_at) {
        use Chalk::Bootstrap::Context;
        return Chalk::Bootstrap::Context->new(
            focus       => $matched_text,
            position    => 0,
            annotations => {
                scan      => true,
                rule_name => $rule_name,
                alt_idx   => $alt_idx,
                predicted => $predicted_at,
            },
        );
    }

    # Create an annotated Context for a completion event.
    # focus is undef because the completed value is wrapped as a child;
    # annotations record the complete event metadata for semiring inspection.
    method _make_complete_context($value, $rule_name, $alt_idx, $pos, $origin) {
        use Chalk::Bootstrap::Context;
        return Chalk::Bootstrap::Context->new(
            focus       => undef,
            children    => [$value],
            position    => $pos,
            annotations => {
                complete  => true,
                rule_name => $rule_name,
                alt_idx   => $alt_idx,
                pos       => $pos,
                origin    => $origin,
            },
        );
    }

    # After prediction, check for already-completed items of the predicted
    # rule at the current position and advance the waiting item. This handles
    # nullable nonterminals (like whitespace _) appearing multiple times in a
    # rule — the second prediction is suppressed but the earlier completion
    # never saw this waiting item, so we combine them here.
    # Uses %completed_at index for O(1) lookup instead of scanning the full chart.
    # Takes core_id, origin, and value directly (no item hashref).
    method _advance_from_completed($waiting_core_id, $waiting_origin, $waiting_value, $symbol, $pos, $chart, $agenda) {
        my $rule_name = $symbol->value();

        # Look up completed items for this rule name with origin == pos at chart pos
        my $completed_refs = $completed_at{$rule_name}{$pos}{$pos};
        return unless defined $completed_refs;

        for my $cref ($completed_refs->@*) {
            my ($c_core_id, $c_origin) = $cref->@*;
            my $completed_val = $self->_chart_get($chart, $pos, $c_core_id, $c_origin);
            next unless defined $completed_val;

            # Advance the waiting item past the completed reference
            my $new_value = $semiring->multiply($waiting_value, $completed_val);

            # Skip if multiply produced zero — don't propagate rejected
            # completions to parent items
            next if $semiring->is_zero($new_value);

            my $new_core_id = $core_index->advance($waiting_core_id);

            if ($self->_chart_has($chart, $pos, $new_core_id, $waiting_origin)) {
                my $existing_val = $self->_chart_get($chart, $pos, $new_core_id, $waiting_origin);
                my $merged_value;
                try {
                    $merged_value = $semiring->add($existing_val, $new_value);
                } catch ($e) {
                    my $rn = $core_index->rule_name_for($new_core_id);
                    my $completed_rule = $symbol->value();
                    die "Ambiguity in advance_from_completed for '$rn' "
                        . "(pos=$pos, origin=$waiting_origin) "
                        . "completing='$completed_rule': $e";
                }
                $self->_chart_set($chart, $pos, $new_core_id, $waiting_origin, $merged_value);
            } else {
                $self->_chart_set($chart, $pos, $new_core_id, $waiting_origin, $new_value);
                push $agenda->@*, [$new_core_id, $waiting_origin];
            }
        }
    }
}
