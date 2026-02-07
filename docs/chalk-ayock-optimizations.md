# ============================================================================
# Chalk Parser with Aycock Optimizations — Pseudo-Perl Walkthrough
# ============================================================================
#
# This file shows how Aycock's dissertation techniques integrate into
# Chalk's existing Earley parser + composite semiring architecture.
#
# Structure:
#   1. Precomputation (grammar construction time)
#      - Core item enumeration
#      - LR(0) DFA construction
#      - Terminal clustering per DFA state
#      - Safe-set static analysis hints
#   2. Modified Chart (runtime)
#      - Bitmap membership instead of hash keys
#      - Safe-set tracking and chart GC
#   3. Modified Parser (runtime)
#      - DFA-based prediction (collapses Predictor)
#      - Lazy semiring initialization
#      - Safe-set fast path for completions
#
# Key insight: Aycock's techniques are about reducing BOOKKEEPING cost.
# Chalk's semiring architecture adds SEMANTIC cost per item. Combining them
# means we reduce bookkeeping AND use the structural information to skip
# semantic work on items that can't contribute to the final parse.
#
# Notation:
#   "CURRENT"  = what Chalk does now
#   "AYCOCK"   = what changes with the optimization
#   "SEMIRING" = how it interacts with composite semirings
# ============================================================================

use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);


# ============================================================================
# PART 1: PRECOMPUTATION — Built once per grammar, reused across all parses
# ============================================================================
#
# Currently, Chalk::Grammar stores rules and precomputes rules_waiting_for.
# With Aycock, we add three precomputed structures:
#   1. Core item enumeration (integer IDs for every rule+dot combination)
#   2. LR(0) DFA (clusters predicted items into states)
#   3. Terminal map per DFA state (which regexes to try at each state)

# --- Core Item Enumeration ---
#
# CURRENT: Each Earley item builds a string key:
#   "Earley|$start_pos|$rule_id|$dot_pos|$end_pos"
# This requires string concatenation + hash lookup for membership testing.
#
# AYCOCK: Enumerate all possible (rule_id, dot_pos) pairs at grammar
# construction time. Each gets a small integer. Membership testing becomes
# a single bit check in a fixed-size bitmap.
#
# For a grammar with R rules and average RHS length L, the number of
# core items is roughly R * (L + 1). For Chalk's 960 rules with ~3-4 avg
# RHS symbols, that's ~4000-5000 core items = ~600 bytes per bitmap.

class Chalk::CoreItemIndex {
    field %item_to_id;    # "rule_id|dot_pos" => integer
    field @id_to_item;    # integer => { rule => $rule, dot_pos => $n }
    field $count :reader = 0;

    method register($rule, $dot_pos) {
        my $key = $rule->id . '|' . $dot_pos;
        return $item_to_id{$key} if exists $item_to_id{$key};

        my $id = $count++;
        $item_to_id{$key} = $id;
        $id_to_item[$id] = { rule => $rule, dot_pos => $dot_pos };
        return $id;
    }

    method id_for($rule, $dot_pos) {
        return $item_to_id{ $rule->id . '|' . $dot_pos };
    }

    method item_for($id) { $id_to_item[$id] }

    # Called during Grammar construction — enumerate ALL core items
    method build_from_grammar($grammar) {
        for my $lhs (keys $grammar->rules->%*) {
            for my $rule ($grammar->rules_for($lhs)) {
                my @rhs = $rule->rhs->@*;
                # Register dot at every position: 0, 1, ..., |RHS|
                for my $dot (0 .. scalar(@rhs)) {
                    $self->register($rule, $dot);
                }
            }
        }
    }
}


# --- LR(0) DFA Construction ---
#
# CURRENT: Predictor iterates over grammar->rules_for($nonterminal),
# creating one EarleyItem object per rule. For Expression with 50 rules,
# that's 50 objects, 50 hash insertions, 50 semiring init_element_from_rule calls.
#
# AYCOCK: Pre-cluster those items into LR(0) DFA states. Each state is a
# set of core items. Split into kernel (dot not at start) and nonkernel
# (dot at start = predictions). Prediction becomes "add one nonkernel
# state" instead of "add N items".
#
# The DFA is built via NFA→DFA subset construction:
#   NFA states: one per core item
#   NFA transitions:
#     [A → α • X β] --X--> [A → α X • β]     (shift on symbol X)
#     [A → α • B β] --ε--> [B → • γ]          (predict nonterminal B)
#   DFA states: ε-closure sets, split into kernel/nonkernel

class Chalk::LR0State {
    field $id          :param :reader;
    field $core_items  :param :reader;    # arrayref of core_item_ids in this state
    field $is_kernel   :param :reader;    # 1 = kernel, 0 = nonkernel (predictions)
    field %transitions;                   # symbol => target state id
    field @terminal_patterns;             # precomputed: regexes expected by this state
    field @nonterminal_syms;              # precomputed: nonterminals expected by this state
    field @final_items;                   # core items where dot is at end (completions)
    field $has_completions :reader = 0;   # quick check: any final items?
    field $is_dead :reader = 0;           # Earley set compression: no NT transitions, not final

    method add_transition($symbol, $target_state_id) {
        $transitions{$symbol} = $target_state_id;
    }

    method transition_on($symbol) { $transitions{$symbol} }

    method set_dead($val) { $is_dead = $val }

    # Precompute what this state expects, for efficient scanning
    # Called once during DFA construction
    method precompute_expectations($core_index, $grammar) {
        my %seen_terminals;
        my %seen_nonterminals;

        for my $core_id ($core_items->@*) {
            my $item = $core_index->item_for($core_id);
            my $rule = $item->{rule};
            my $dot  = $item->{dot_pos};
            my @rhs  = $rule->rhs->@*;

            if ($dot >= scalar(@rhs)) {
                # Final item — this state contains completions
                push @final_items, $core_id;
                $has_completions = 1;
                next;
            }

            my $next_sym = $rhs[$dot];
            if ($grammar->is_nonterminal($next_sym)) {
                $seen_nonterminals{$next_sym} = 1;
            } else {
                # Terminal — could be string literal or regex
                my $key = ref($next_sym) eq 'Regexp' ? "$next_sym" : $next_sym;
                unless ($seen_terminals{$key}++) {
                    push @terminal_patterns, $next_sym;
                }
            }
        }

        @nonterminal_syms = keys %seen_nonterminals;
    }
}

class Chalk::LR0DFA {
    field @states;                          # all DFA states
    field %nonkernel_for;                   # nonterminal => nonkernel state id
    field $core_index :param :reader;       # the CoreItemIndex
    field $grammar    :param :reader;

    # Build the DFA from grammar via NFA subset construction
    # This is the most complex precomputation step
    method build() {
        # --- Step 1: Build NFA ---
        # Each core item (rule_id, dot_pos) is an NFA state.
        # Transitions:
        #   (rule, dot) --symbol--> (rule, dot+1)    when RHS[dot] == symbol
        #   (rule, dot) --ε-->     (rule', 0)        when RHS[dot] is nonterminal B
        #                                             and rule' has LHS == B

        # --- Step 2: Compute ε-closures to get DFA states ---
        # Start state: ε-closure of { (S' → • S, 0) }
        # Each DFA state = a set of NFA states (core items)
        # Transitions: for each symbol X, the DFA state reachable from
        #   the current state on X is ε-closure(move(current, X))

        # --- Step 3: Split each DFA state into kernel + nonkernel ---
        # Kernel: items where dot > 0, plus the initial item
        # Nonkernel: items where dot == 0 (these came from ε-transitions)
        # Store nonkernel states indexed by the nonterminal that predicts them

        # --- Step 4: Precompute expectations for each state ---
        # For each state, categorize what the dot is before:
        #   - terminals (regex patterns to try during scanning)
        #   - nonterminals (for further prediction / completion)
        #   - nothing (final items, for completion)

        # --- Step 5: Mark dead states (Earley set compression) ---
        # A state is "dead" if it has no nonterminal transitions AND
        # contains no final items. Such states can never cause new items
        # to be added and contribute nothing to the parse.

        # Pseudocode for the subset construction:
        my @worklist;
        my %state_registry;  # frozen set of core_ids => state_id

        # Initial state from augmented grammar start rule
        my $start_rule = $grammar->start_rule;
        my $start_core = $core_index->id_for($start_rule, 0);
        my $start_closure = $self->epsilon_closure([$start_core]);

        my ($kernel, $nonkernel) = $self->split_kernel_nonkernel($start_closure);
        # ... register states, add to worklist, iterate transitions ...

        # After construction, precompute expectations for each state
        for my $state (@states) {
            $state->precompute_expectations($core_index, $grammar);
        }

        # Mark dead states
        for my $state (@states) {
            if (!$state->has_completions && !@{[$state->nonterminal_syms]}) {
                $state->set_dead(1);
            }
        }
    }

    method epsilon_closure($core_ids) {
        # Standard ε-closure: follow all prediction edges transitively
        # For core item (rule, dot) where RHS[dot] is nonterminal B,
        # add all (rule', 0) where rule' has LHS == B
        # Continue until fixed point
        # ...
    }

    method split_kernel_nonkernel($core_id_set) {
        # Kernel: dot > 0 or initial item
        # Nonkernel: dot == 0
        # Returns (kernel_state, nonkernel_state) — either may be undef
        # ...
    }

    # Key lookup: what nonkernel state do we enter when predicting nonterminal B?
    method prediction_state_for($nonterminal) {
        return $nonkernel_for{$nonterminal};
    }

    method state($id) { $states[$id] }
}


# ============================================================================
# PART 2: MODIFIED CHART — Bitmap membership + safe-set tracking
# ============================================================================
#
# The chart is where the biggest constant-factor wins live.
# Two changes: bitmap membership testing, and safe-set GC.

class Chalk::AycockChart {
    field $core_index :param;   # CoreItemIndex for bitmap sizing
    field $dfa        :param;   # LR0DFA for state lookups
    field $semiring   :param;

    # --- Bitmap membership (replaces %chart hash for presence testing) ---
    #
    # CURRENT: has_item() does: exists($chart{"Earley|$start|$rule_id|$dot|$end"})
    # AYCOCK: One bitmap per (position, parent_position) pair.
    #         Bit N is set iff core item N exists with that (end_pos, start_pos).
    #
    # In practice, we use a two-level structure:
    #   @bitmaps[$end_pos] = { $start_pos => $bitmap_string }
    # where $bitmap_string is a vec() string with one bit per core item.

    field @bitmaps;             # [$end_pos]{$start_pos} = vec string
    field @elements;            # [$end_pos]{$core_id}{$start_pos} = semiring element
    field @items_by_end;        # [$end_pos] = [ {core_id, start_pos}, ... ]

    # --- Radix trees for duplicate parent pointers (Aycock §4.1.4) ---
    # When the same core item appears with multiple start positions,
    # the bitmap alone can't distinguish them. We need the radix tree
    # for the relatively rare case of >1 parent per core.
    # In practice, most core items have exactly one parent per position,
    # so we optimize for that case with a "first parent" cache.

    field @first_parent;        # [$end_pos]{$core_id} = first start_pos seen
    field @radix_trees;         # [$end_pos]{$core_id} = radix tree (only if >1 parent)

    method has_item($core_id, $start_pos, $end_pos) {
        my $bm = $bitmaps[$end_pos]{$start_pos} // return 0;
        return vec($bm, $core_id, 1);
    }

    method add_item($core_id, $start_pos, $end_pos, $element) {
        # Step 1: Bitmap check
        $bitmaps[$end_pos]{$start_pos} //= '';
        if (vec($bitmaps[$end_pos]{$start_pos}, $core_id, 1)) {
            # Item already exists — merge via semiring add()
            my $existing = $elements[$end_pos]{$core_id}{$start_pos};
            $elements[$end_pos]{$core_id}{$start_pos} = $existing + $element;
            return 0;  # not new
        }

        # Step 2: Set bit and store element
        vec($bitmaps[$end_pos]{$start_pos}, $core_id, 1) = 1;
        $elements[$end_pos]{$core_id}{$start_pos} = $element;

        # Step 3: Index for agenda iteration
        push $items_by_end[$end_pos]->@*, {
            core_id   => $core_id,
            start_pos => $start_pos,
        };

        return 1;  # new item added
    }

    method get_element($core_id, $start_pos, $end_pos) {
        return $elements[$end_pos]{$core_id}{$start_pos};
    }

    # --- Safe-Set Tracking (Aycock Chapter 6) ---
    #
    # A set S_i is "safe" if no items in it can be reached from any
    # future set via the Completer. Equivalently: S_i is safe when
    # no items in any set S_j (j >= i) point back to S_i as a parent.
    #
    # PRACTICAL ALGORITHM:
    # Track the minimum parent pointer ("oldest reference") across all
    # items in the current set. Everything before that minimum is safe
    # and can be GC'd.
    #
    # For Chalk, "GC'd" means:
    #   - Drop the bitmap for that position
    #   - Drop all semiring elements (SPPF nodes, semantic contexts,
    #     type inference state, precedence data) for that position
    #   - Keep only committed semantic results that have already been
    #     folded into later items via multiply()

    field $oldest_live_pos = 0;     # Minimum position we must retain
    field @committed;               # [$pos] = 1 if pos has been GC'd

    method update_safe_window($current_pos) {
        # Find the minimum start_pos (parent pointer) across all items
        # in the current set. Everything before that is safe to GC.
        my $min_parent = $current_pos;

        for my $item ($items_by_end[$current_pos]->@*) {
            $min_parent = $item->{start_pos}
                if $item->{start_pos} < $min_parent;
        }

        # GC positions from $oldest_live_pos up to (but not including) $min_parent
        for my $pos ($oldest_live_pos .. $min_parent - 1) {
            next if $committed[$pos];
            $self->gc_position($pos);
            $committed[$pos] = 1;
        }

        $oldest_live_pos = $min_parent;
    }

    method gc_position($pos) {
        # Release all data structures for this position.
        # The semiring elements here have already been multiplied into
        # their consumers during completion, so they're no longer needed.
        #
        # SEMIRING INTERACTION: This is safe because:
        #   multiply() copies the relevant data into the new element
        #   (children contexts, type envs, SPPF nodes are all value-like)
        #   The original elements at $pos are unreachable after this point.
        delete $bitmaps[$pos];
        delete $elements[$pos];
        # Keep $items_by_end[$pos] as lightweight metadata if needed for debugging
    }

    # --- Items waiting for a symbol at a position ---
    # CURRENT: Hash of arrays: waiting_for{symbol}{pos} = [items]
    # AYCOCK: Same structure, but items are (core_id, start_pos) tuples
    # instead of full EarleyItem objects. The DFA state tells us what
    # each core item is waiting for, so we can derive this from the
    # items_by_end index.

    field %waiting_for;    # {symbol}{pos} = [ {core_id, start_pos}, ... ]

    method items_waiting_for($symbol, $pos) {
        return $waiting_for{$symbol}{$pos}->@*
            if exists $waiting_for{$symbol} && exists $waiting_for{$symbol}{$pos};
        return;
    }

    method register_waiting($symbol, $pos, $core_id, $start_pos) {
        $waiting_for{$symbol}{$pos} //= [];
        push $waiting_for{$symbol}{$pos}->@*, {
            core_id   => $core_id,
            start_pos => $start_pos,
        };
    }
}


# ============================================================================
# PART 3: MODIFIED PARSER — The main event
# ============================================================================
#
# This is where all the pieces come together. The three Earley operations
# (Predict, Scan, Complete) are restructured around DFA states.

class Chalk::AycockParser {
    field $grammar  :param :reader;
    field $semiring :param :reader;
    field $dfa      :param :reader;       # precomputed LR0DFA
    field $core_index :param :reader;     # precomputed CoreItemIndex

    method parse_string($input) {
        my $chart = Chalk::AycockChart->new(
            core_index => $core_index,
            dfa        => $dfa,
            semiring   => $semiring,
        );

        # Seed the chart with the start state
        # CURRENT: Creates one EarleyItem per start rule
        # AYCOCK: Adds the start DFA state (which contains all start rules)
        my $start_state = $dfa->state(0);   # State 0 = initial kernel
        for my $core_id ($start_state->core_items->@*) {
            my $item_info = $core_index->item_for($core_id);
            my $element = $semiring->init_element_from_rule(
                $item_info->{rule}, 0, 0
            );
            $chart->add_item($core_id, 0, 0, $element);
        }

        # Also add the nonkernel state for the start symbol's predictions
        $self->predict_via_dfa($grammar->start_symbol, 0, $chart);

        # Main parse loop
        my $pos = 0;
        my $input_length = length($input);

        while ($pos <= $input_length) {
            $self->process_position($pos, $chart, $input);

            # --- Safe-set GC (Aycock Chapter 6) ---
            # After processing each position, check if old positions
            # can be garbage collected.
            $chart->update_safe_window($pos);

            $pos++;
        }

        return $chart->goal_value($grammar->start_symbol, $input_length);
    }

    # -----------------------------------------------------------------------
    # PREDICT — The biggest structural change
    # -----------------------------------------------------------------------
    #
    # CURRENT predict():
    #   for my $rule ($grammar->rules_for($nonterminal)) {
    #       my $item = Chalk::EarleyItem->new(
    #           start_pos => $pos, rule => $rule,
    #           dot_pos => 0, end_pos => $pos
    #       );
    #       my $element = $semiring->init_element_from_rule($rule, $pos, $pos);
    #       $chart->add_element($item, $element);
    #       push @agenda, $item;
    #   }
    #
    # For Expression with 50 rules, this creates 50 objects and calls
    # init_element_from_rule 50 times (which propagates through all
    # composite semirings).
    #
    # AYCOCK predict_via_dfa():
    #   Look up the nonkernel DFA state for this nonterminal.
    #   That state contains ALL the predicted core items pre-clustered.
    #   Add one state reference. Defer semiring initialization.

    method predict_via_dfa($nonterminal, $pos, $chart) {
        my $nk_state_id = $dfa->prediction_state_for($nonterminal);
        return unless defined $nk_state_id;

        my $nk_state = $dfa->state($nk_state_id);

        # Skip dead states (Earley set compression — Aycock §4.3)
        # Dead states have no NT transitions and no completions,
        # so they can never contribute to the parse.
        return if $nk_state->is_dead;

        for my $core_id ($nk_state->core_items->@*) {
            next if $chart->has_item($core_id, $pos, $pos);

            # --- LAZY SEMIRING INITIALIZATION ---
            #
            # CURRENT: init_element_from_rule() is called immediately for
            # every predicted item. With composite semirings, this means:
            #   - Semantic: create EvalContext with empty children, env, rule
            #   - SPPF: create placeholder forest node
            #   - Precedence: create neutral precedence element
            #   - TypeInference: create top-type element
            #
            # AYCOCK OPTIMIZATION: Most predicted items are dead ends.
            # Aycock measured 16% unused items in Java; with Chalk's 960
            # rules and flat expression grammar, it's likely higher.
            #
            # STRATEGY: Create a LIGHTWEIGHT placeholder element for
            # predicted items. Only materialize the full composite
            # semiring element when the item first participates in a
            # scan or completion (i.e., when it proves it's on a viable
            # parse path).
            #
            # The placeholder must satisfy the semiring contract:
            #   - Has a valid mul_id behavior for multiply()
            #   - Can be promoted to a full element on demand
            #   - Is cheap to create (no composite delegation)

            my $item_info = $core_index->item_for($core_id);
            my $element = $self->lazy_init_element($item_info->{rule}, $pos);

            $chart->add_item($core_id, $pos, $pos, $element);

            # Add to agenda — but items from nonkernel states only need
            # processing if they can immediately scan or have nullable
            # first symbols. Most just sit and wait for scans.
            # (This is a further optimization opportunity.)
        }

        # Handle nullable nonterminals (Aycock Chapter 7 / ε-DFA)
        # If the nonterminal is nullable, also advance the dot past it
        # in the calling item. This is the same as the current
        # Aycock-Horspool nullable optimization.
        if ($grammar->is_nullable($nonterminal)) {
            # ... advance dot in waiting items (same as current code)
        }
    }

    # Lazy element: defers full semiring init until proven needed
    method lazy_init_element($rule, $pos) {
        # Option A: Always create full elements (current behavior, safe)
        return $semiring->init_element_from_rule($rule, $pos, $pos);

        # Option B: Create lightweight proxy that materializes on first use
        # return Chalk::Semiring::LazyElement->new(
        #     semiring => $semiring,
        #     rule     => $rule,
        #     pos      => $pos,
        # );
        #
        # LazyElement would implement multiply() and add() by first
        # calling $semiring->init_element_from_rule() to get the real
        # element, then delegating. After materialization, it replaces
        # itself in the chart.
        #
        # Risk: adds indirection cost to every element operation.
        # Worth profiling to see if deferred init saves more than
        # the proxy overhead costs.
    }


    # -----------------------------------------------------------------------
    # SCAN — Terminal matching, now clustered by DFA state
    # -----------------------------------------------------------------------
    #
    # CURRENT: For each item in the agenda, if it's waiting for a terminal,
    # try to regex-match at the current position. Each item is tested
    # independently, even if multiple items expect the same terminal.
    #
    # AYCOCK: DFA states precompute which terminals they expect.
    # Group all items by their DFA state, then match each terminal
    # pattern once per state instead of once per item.
    #
    # For scannerless parsing, this is significant: if 20 items all
    # expect /\s*/, we match it once instead of 20 times.

    method scan_position($pos, $chart, $input) {
        my @items_here = $chart->items_at_end($pos);

        # Group items by their DFA state
        # (Items in the same DFA state expect the same terminals)
        my %by_state;
        for my $item (@items_here) {
            my $core_id = $item->{core_id};
            # Map core_id to its DFA state (precomputed in DFA construction)
            my $state_id = $dfa->state_for_core($core_id);
            push $by_state{$state_id}->@*, $item;
        }

        # For each state, try each terminal pattern once
        for my $state_id (keys %by_state) {
            my $state = $dfa->state($state_id);
            my @items_in_state = $by_state{$state_id}->@*;

            for my $terminal ($state->terminal_patterns->@*) {
                my $pattern = ref($terminal) eq 'Regexp'
                    ? $terminal
                    : qr/(\Q$terminal\E)/;

                pos($input) = $pos;
                next unless $input =~ /\G$pattern/;

                my ($pattern_name, $matched_text) = %+;
                $matched_text //= $1;

                my $token = $self->make_token($matched_text, $pattern_name);
                my $new_end = $pos + length($matched_text);

                # Get the target DFA state for this terminal transition
                my $target_state_id = $state->transition_on($terminal);

                # Now advance ALL items in this state that were waiting
                # for this terminal. The DFA transition tells us exactly
                # which core item each advances to.
                for my $item (@items_in_state) {
                    my $element = $chart->get_element(
                        $item->{core_id}, $item->{start_pos}, $pos
                    );
                    next unless defined $element;

                    # Materialize lazy element if needed
                    # $element = $element->materialize() if $element isa LazyElement;

                    # on_scan — same as current, but only called once
                    # per (state, terminal) combination
                    my $scanned = $semiring->on_scan(
                        $item, $element, $pos, $token, $pattern_name
                    );

                    # The advanced core_id comes from the DFA transition
                    my $advanced_core = $core_index->advance(
                        $item->{core_id}
                    );

                    $chart->add_item(
                        $advanced_core,
                        $item->{start_pos},
                        $new_end,
                        $element * $scanned,  # multiply combines sequential
                    );
                }
            }
        }
    }


    # -----------------------------------------------------------------------
    # COMPLETE — Safe-set fast path + standard completion
    # -----------------------------------------------------------------------
    #
    # This is where the safe-set analysis pays off for semirings.
    #
    # CURRENT complete():
    #   1. Call on_complete() to fire semantic actions
    #   2. Look up items_waiting_for(lhs, start_pos)
    #   3. For each waiting item, multiply elements and advance dot
    #   4. If the new item already exists, call add() to disambiguate
    #      (this means evaluating BOTH derivations via on_complete,
    #       then letting add() pick the winner)
    #
    # AYCOCK: Add a fast path for deterministic completions.
    #   - If there's exactly one waiting item and no ambiguity,
    #     skip the add() branch entirely.
    #   - If the current position is in a "safe" region (no future
    #     completions can reach back here), mark the result as
    #     committed — it won't change, so we can GC aggressively.

    method complete($core_id, $start_pos, $end_pos, $element, $chart, $agenda) {
        my $item_info = $core_index->item_for($core_id);
        my $rule = $item_info->{rule};
        my $lhs  = $rule->lhs;

        # --- on_complete: fire semantic actions ---
        # Same as current — delegates through Composite to all semirings
        $element = $semiring->on_complete_item($core_id, $element);

        # Update chart with evaluated element
        $chart->update_element($core_id, $start_pos, $end_pos, $element);

        # --- Find waiting items ---
        my @waiting = $chart->items_waiting_for($lhs, $start_pos);

        # --- Leo optimization (retained from current parser) ---
        # Deterministic right-recursive chains get Leo items
        # This is orthogonal to Aycock's optimizations
        if (@waiting == 1 && $self->is_leo_candidate($waiting[0], $rule)) {
            $self->create_leo_item($waiting[0], $element, $end_pos, $chart, $agenda);
            return;
        }

        # --- SAFE-SET FAST PATH ---
        #
        # If there's exactly one item waiting AND the new advanced item
        # doesn't already exist in the chart, this completion is
        # unambiguous. We can skip the add() disambiguation entirely.
        #
        # WHY THIS MATTERS FOR SEMIRINGS:
        # The add() path currently requires evaluating on_complete()
        # on the new derivation BEFORE merging, so that add() can
        # compare fully-evaluated alternatives. This means we sometimes
        # build IR nodes, type-check, compute precedence — all for a
        # derivation that will be immediately discarded.
        #
        # The fast path skips all of that. At statement boundaries,
        # block openings, unambiguous operators (most of the grammar),
        # completion is deterministic and we go straight through.

        for my $waiting (@waiting) {
            my $waiting_element = $chart->get_element(
                $waiting->{core_id}, $waiting->{start_pos}, $start_pos
            );
            next unless defined $waiting_element;

            # Semiring multiply: combine sequential components
            my $combined = $waiting_element * $element;

            # What core item does the waiting item advance to?
            my $advanced_core = $core_index->advance($waiting->{core_id});

            # Check if this is a new item or an existing one (ambiguity)
            my $is_new = !$chart->has_item(
                $advanced_core, $waiting->{start_pos}, $end_pos
            );

            if ($is_new) {
                # *** FAST PATH: unambiguous completion ***
                # No add() needed. Just store and continue.
                $chart->add_item(
                    $advanced_core,
                    $waiting->{start_pos},
                    $end_pos,
                    $combined
                );

                push $agenda->@*, {
                    core_id   => $advanced_core,
                    start_pos => $waiting->{start_pos},
                };
            }
            else {
                # *** SLOW PATH: ambiguous completion ***
                # Must call on_complete() on this new derivation
                # so add() can compare fully-evaluated alternatives.
                #
                # This is the current behavior — evaluate both,
                # let add() (which delegates to Precedence, then
                # Semantic child-count) pick the winner.

                my $new_item_info = $core_index->item_for($advanced_core);
                if ($new_item_info->{dot_pos} >= scalar($new_item_info->{rule}->rhs->@*)) {
                    # Advanced item is complete — evaluate before merging
                    $combined = $semiring->on_complete_item($advanced_core, $combined);
                }

                # Merge via add() — the semiring picks the winner
                # This is: existing_element ⊕ combined
                $chart->merge_item(
                    $advanced_core,
                    $waiting->{start_pos},
                    $end_pos,
                    $combined
                );
            }
        }
    }


    # -----------------------------------------------------------------------
    # PROCESS_POSITION — Ties predict/scan/complete together
    # -----------------------------------------------------------------------

    method process_position($pos, $chart, $input) {
        my @agenda = $chart->items_at_end($pos);

        while (my $item = shift @agenda) {
            my $core_id   = $item->{core_id};
            my $start_pos = $item->{start_pos};

            my $element = $chart->get_element($core_id, $start_pos, $pos);
            next unless defined $element;

            my $item_info = $core_index->item_for($core_id);
            my $rule = $item_info->{rule};
            my $dot  = $item_info->{dot_pos};
            my @rhs  = $rule->rhs->@*;

            if ($dot >= scalar(@rhs)) {
                # --- COMPLETE ---
                $self->complete(
                    $core_id, $start_pos, $pos,
                    $element, $chart, \@agenda
                );
            }
            else {
                my $next_sym = $rhs[$dot];
                if ($grammar->is_nonterminal($next_sym)) {
                    # --- PREDICT ---
                    # DFA-based: add one nonkernel state instead of N items
                    $self->predict_via_dfa($next_sym, $pos, $chart);

                    # Register this item as waiting for $next_sym
                    $chart->register_waiting($next_sym, $pos, $core_id, $start_pos);

                    # Handle nullable (Aycock-Horspool, same as current)
                    if ($grammar->is_nullable($next_sym)) {
                        my $advanced_core = $core_index->advance($core_id);
                        unless ($chart->has_item($advanced_core, $start_pos, $pos)) {
                            $chart->add_item($advanced_core, $start_pos, $pos, $element);
                            push @agenda, {
                                core_id   => $advanced_core,
                                start_pos => $start_pos,
                            };
                        }
                    }
                }
                else {
                    # --- SCAN ---
                    # Terminal matching happens here (scannerless)
                    # With DFA state clustering, could batch this,
                    # but the per-item approach still works correctly.
                    my $pattern = $rule->terminal_to_regex($next_sym);
                    pos($input) = $pos;
                    if ($input =~ /\G$pattern/) {
                        my ($pattern_name, $matched_text) = %+;
                        $matched_text //= $1;
                        my $token = $self->make_token($matched_text, $pattern_name);
                        my $new_end = $pos + length($matched_text);

                        my $scanned = $semiring->on_scan(
                            $item, $element, $pos, $token, $pattern_name
                        );
                        my $advanced_core = $core_index->advance($core_id);

                        $chart->add_item(
                            $advanced_core, $start_pos, $new_end,
                            $element * $scanned
                        );
                    }
                }
            }
        }
    }
}


# ============================================================================
# SUMMARY: What changes, what stays
# ============================================================================
#
# STAYS THE SAME:
#   - Composite semiring architecture (SPPF, Semantic, Precedence, TypeInference)
#   - multiply() for sequential composition
#   - add() for disambiguation
#   - on_complete() for semantic action firing
#   - on_scan() for terminal processing
#   - Leo optimization for right-recursive chains
#   - Nullable handling (Aycock-Horspool, already present)
#   - Scannerless parsing (terminals are regexes)
#
# CHANGES:
#   ┌─────────────────────────┬──────────────────────────────────────┐
#   │ Current                 │ With Aycock                         │
#   ├─────────────────────────┼──────────────────────────────────────┤
#   │ EarleyItem objects      │ (core_id, start_pos) integer tuples │
#   │ String key membership   │ Bitmap vec() membership             │
#   │ Hash-based chart        │ Positional arrays + bitmaps         │
#   │ N items per prediction  │ 1 DFA state per prediction          │
#   │ Eager semiring init     │ Lazy init (deferred until needed)   │
#   │ Retain full chart       │ GC safe positions (90%+ savings)    │
#   │ Always run add()        │ Fast-path skip for unambiguous      │
#   │ Per-item terminal match │ Per-state terminal clustering       │
#   │ No dead item pruning    │ Earley set compression              │
#   └─────────────────────────┴──────────────────────────────────────┘
#
# EXPECTED IMPACT ON 960-RULE CHALK GRAMMAR:
#   - Object allocation: ~80% reduction (no EarleyItem objects)
#   - Prediction cost: ~90% reduction (DFA state clustering)
#   - Memory usage: ~90% reduction for long inputs (safe-set GC)
#   - Disambiguation overhead: ~70% reduction (fast-path skip)
#   - Terminal matching: ~50% reduction (state-based batching)
#
# IMPLEMENTATION ORDER (by bang-for-buck):
#   1. CoreItemIndex + bitmap membership (low risk, immediate wins)
#   2. Safe-set chart GC (high memory impact, moderate complexity)
#   3. LR0DFA construction + predict_via_dfa (big refactor, big payoff)
#   4. Terminal clustering (needs DFA, moderate benefit for scannerless)
#   5. Lazy semiring init (needs profiling to validate savings > overhead)
#   6. Earley set compression (easy addition once DFA exists)
#
# SELF-HOSTING INTERACTION:
#   When Chalk compiles itself, the LR(0) DFA is built from Chalk's own
#   grammar. The DFA states become static data in the generated XS code.
#   This means the precomputation cost is paid once at build time, and
#   the runtime parser operates on precomputed integer tables — which
#   is exactly what SHALLOW (Aycock §4.3) does, just targeting XS
#   instead of C.

