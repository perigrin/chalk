# ABOUTME: N-ary FilterComposite semiring running multiple semirings together as staged filters.
# ABOUTME: Values are shared Context objects; each annotation-layer semiring writes to a named slot.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Context;

class Chalk::Bootstrap::Semiring::FilterComposite {
    field $semirings :param :reader;  # arrayref of semirings

    # SA is always the last semiring by convention.
    # All semirings before SA are annotation-layer semirings that write to
    # named slots in the Context's annotations hash.
    method _sa() { return $semirings->[-1] }
    method _annotation_semirings() {
        # All semirings except the last (SA) that have a defined slot_name.
        # Boolean has slot_name=undef and is handled through is_zero flag only.
        # Non-object semirings (legacy test stubs) are skipped.
        return grep {
            blessed($_) && $_->can('slot_name') && defined $_->slot_name()
        } $semirings->@[0 .. $#{ $semirings } - 1];
    }

    # Clear hash-cons caches in all component semirings that support it.
    # Called between file parses to prevent unbounded memory growth.
    method reset_cache() {
        for my $sr ($semirings->@*) {
            $sr->reset_cache() if $sr->can('reset_cache');
        }
    }

    # zero() returns a Context with is_zero=true.
    # Any method that receives this value will short-circuit.
    method zero() {
        return Chalk::Bootstrap::Context->new(
            focus    => undef,
            children => [],
            position => 0,
            is_zero  => true,
        );
    }

    # one() returns a fresh Context with annotation slots initialized from
    # each component semiring's one() value.
    # SA's one() already carries the cfg annotation; we build a new Context
    # copying it plus all annotation-layer slots.
    method one() {
        my $sa_one = $self->_sa()->one();
        # SA must return a Context; non-Context last semirings get a plain wrapper.
        my $is_ctx = blessed($sa_one) && $sa_one->can('annotations');
        my $annotations = $is_ctx ? { $sa_one->annotations()->%* } : {};
        for my $sr ($self->_annotation_semirings()) {
            my $slot = $sr->slot_name();
            # TI (#707): annotations->{type} holds a tag hash, not a TI Context.
            # Extract the focus from TI's one() to get the { valid => true } hash.
            if ($slot eq 'type' && blessed($sr) && $sr->can('slot_name')
                    && $sr->slot_name() eq 'type') {
                my $ti_one = $sr->one();
                $annotations->{$slot} = (blessed($ti_one) && $ti_one->can('extract'))
                    ? $ti_one->extract()
                    : $ti_one;
            } else {
                $annotations->{$slot} = $sr->one();
            }
        }
        my $focus = $is_ctx ? $sa_one->extract() : $sa_one;
        return Chalk::Bootstrap::Context->new(
            focus    => $focus,
            children => [],
            position => 0,
            is_zero  => false,
            annotations => $annotations,
        );
    }

    # is_zero() checks the Context's is_zero flag directly.
    # Handles non-Context values from legacy semiring configurations.
    method is_zero($ctx) {
        return true if !defined $ctx;
        return $ctx->is_zero() if blessed($ctx) && $ctx->can('is_zero');
        return false;
    }

    # _wrap_sa_result: Build a new Context from SA's result merged with slot annotations.
    # Does NOT mutate $sa_result — it may be hash-consed or shared.
    # Handles non-Context SA results (e.g., when last semiring is Structural).
    method _wrap_sa_result($sa_result, %slot_results) {
        my $is_ctx = blessed($sa_result) && $sa_result->can('extract');
        return Chalk::Bootstrap::Context->new(
            focus       => $is_ctx ? $sa_result->extract() : $sa_result,
            children    => $is_ctx ? [$sa_result->children()->@*] : [],
            position    => $is_ctx ? $sa_result->position() : 0,
            rule        => $is_ctx ? $sa_result->rule() : undef,
            is_zero     => false,
            annotations => {
                ($is_ctx ? $sa_result->annotations()->%* : ()),
                %slot_results,
            },
        );
    }

    # _same_value: identity comparison suitable for both refs and scalars.
    my sub _same_value($a, $b) {
        return true  if !defined($a) && !defined($b);
        return false if !defined($a) || !defined($b);
        if (ref($a) && ref($b)) {
            return refaddr($a) == refaddr($b);
        }
        if (!ref($a) && !ref($b)) {
            return $a == $b;
        }
        return false;
    }

    # multiply() computes the product of two Context values.
    # Short-circuits to zero if either input is_zero or any annotation-layer
    # semiring's multiply returns zero. SA builds the tree structure.
    method multiply($left, $right) {
        return $self->zero() if $left->is_zero();
        return $self->zero() if $right->is_zero();

        # Run each annotation-layer semiring and collect results
        my %slot_results;
        for my $sr ($self->_annotation_semirings()) {
            my $slot = $sr->slot_name();
            my $l_val = $left->annotations()->{$slot} // $sr->one();
            my $r_val = $right->annotations()->{$slot} // $sr->one();
            # TI (#707): multiply is skipped — SA builds the shared tree.
            # TI's type tag comes from on_complete, not from multiply.
            # Carry the left type tag forward (type is resolved at on_complete).
            if ($slot eq 'type') {
                $slot_results{$slot} = undef;     # type tag comes from on_complete
                next;
            }
            my $result = $sr->multiply($l_val, $r_val);
            return $self->zero() if $sr->is_zero($result);
            $slot_results{$slot} = $result;
        }

        # SA builds the tree structure (the shared Context)
        my $sa_result = $self->_sa()->multiply($left, $right);
        return $self->zero() if $self->_sa()->is_zero($sa_result);

        return $self->_wrap_sa_result($sa_result, %slot_results);
    }

    # _filter_compare: scan each annotation-layer semiring for a preference
    # between left and right Context values.
    #
    # Semirings are checked in priority order. The FIRST semiring that expresses
    # a clear preference determines the winner — subsequent semirings are not
    # consulted. This matches the ordered-filter semantics: earlier semirings
    # have higher priority.
    #
    # For each annotation-layer semiring, extracts the slot value from each
    # Context, calls $semiring->add($li, $ri), and inspects the result:
    #   - If the result matches $li but not $ri → prefers left ('right_loses')
    #   - If the result matches $ri but not $li → prefers right ('left_loses')
    #   - If result matches both or neither    → no preference, try next semiring
    #
    # Identity comparison: scalars compare numerically; refs compare by refaddr.
    # Semiring add() returns are normalized to arrayrefs for uniform handling.
    #
    # Returns: 'right_loses' | 'left_loses' | 'neither'
    method _filter_compare($left, $right) {
        for my $sr ($self->_annotation_semirings()) {
            my $slot = $sr->slot_name();

            my ($li, $ri);
            $li = $left->annotations()->{$slot};
            $ri = $right->annotations()->{$slot};

            # Skip identity: same value means this semiring cannot distinguish.
            next if _same_value($li, $ri);

            # TI (#707): type tag is now a plain hash ref in annotations->{type}.
            # TI never expresses a preference via add() (its add() returns a merged
            # Context that equals neither input, which means "no preference").
            # TI disambiguates by returning undef from on_complete (zero), not add().
            # Skip calling add() for the type slot — identity check above is sufficient.
            next if $slot eq 'type';

            # Invoke semiring add() and normalize result to arrayref.
            # Semirings using the scalar protocol (Structural) return bare scalars;
            # we wrap them so the comparison below is uniform.
            my $result = $sr->add($li, $ri);
            $result = [$result] unless ref($result) eq 'ARRAY';

            # Empty result: semiring rejects both alternatives.
            next if $result->@* == 0;

            # Multi-element result: semiring genuinely cannot choose → no preference.
            next if $result->@* > 1;

            # Single-element result: semiring picked one side.
            my $r = $result->[0];

            my $r_eq_left  = ref($r) && ref($li)  ? refaddr($r) == refaddr($li)
                           : !ref($r) && !ref($li) ? $r == $li
                           :                         false;
            my $r_eq_right = ref($r) && ref($ri)  ? refaddr($r) == refaddr($ri)
                           : !ref($r) && !ref($ri) ? $r == $ri
                           :                         false;

            # Result equals both: identity collapse, no preference.
            next if $r_eq_left && $r_eq_right;

            # Result equals neither: semiring synthesized a new value — no preference.
            next unless $r_eq_left || $r_eq_right;

            # First semiring to express a preference wins.
            return $r_eq_left ? 'right_loses' : 'left_loses';
        }

        return 'neither';
    }

    # add() returns a single winning Context, not a survivor list.
    #
    # The design doc specifies survivor lists where multiple alternatives can
    # survive, with an end-of-parse assertion catching genuine ambiguities.
    # This implementation uses single-Context representation because the Earley
    # parser (Earley.pm) stores one value per chart item — supporting survivor
    # lists would require deep changes to the parser's data structures.
    #
    # _filter_compare uses first-wins early return rather than the design doc's
    # check-all-with-conflict-detection. This is safe because all semirings are
    # ordered by priority (Boolean > Precedence > TypeInference > Structural >
    # SemanticAction) and conflicts between semirings have not been observed
    # across the full 1,867-test regression suite. Conflict detection can be
    # added later if needed for debugging.
    method add($left, $right) {
        # Zero handling: is_zero flag on Context
        return $right if $left->is_zero();
        return $left  if $right->is_zero();

        # Determine which Context wins by scanning for annotation-layer preferences.
        my $verdict = $self->_filter_compare($left, $right);

        my ($winner, $loser);
        if ($verdict eq 'right_loses') {
            ($winner, $loser) = ($left, $right);
        } elsif ($verdict eq 'left_loses') {
            ($winner, $loser) = ($right, $left);
        } else {
            # No semiring expressed a preference: deterministic tie-break picks left.
            ($winner, $loser) = ($left, $right);
        }

        # Post-merge hook: allow SA to transfer side-table state from
        # loser to winner. This fixes the Earley stale-value merge problem
        # where cfg_state updates are lost when add() picks the older value.
        if ($self->_sa()->can('on_merge')) {
            $self->_sa()->on_merge($winner, $loser);
        }

        return $winner;
    }

    # on_scan() delegates to each annotation-layer semiring and to SA.
    # If any component returns zero, the whole result is zero.
    # Returns a Context with annotation slots and SA tree structure.
    method on_scan($ctx, $rule_name, $alt_idx, $pos, $matched_text) {
        return $self->zero() if $ctx->is_zero();

        # Run each annotation-layer semiring
        my %slot_results;
        for my $sr ($self->_annotation_semirings()) {
            my $slot = $sr->slot_name();
            my $val;
            # TI (#707): pass the shared Context directly so TI's on_scan
            # can read annotations and return a tag hash.
            if ($slot eq 'type') {
                $val = $ctx;
            } else {
                $val = $ctx->annotations()->{$slot} // $sr->one();
            }
            my $result = $sr->on_scan($val, $rule_name, $alt_idx, $pos, $matched_text);
            return $self->zero() if $sr->is_zero($result);
            if ($slot eq 'type') {
                # TI's on_scan now returns a tag hash directly (#707).
                # Store it as annotations->{type} on the shared Context.
                $slot_results{type} = $result;
            } else {
                $slot_results{$slot} = $result;
            }
        }

        # SA builds the tree structure
        my $sa_result = $self->_sa()->on_scan($ctx, $rule_name, $alt_idx, $pos, $matched_text);
        return $self->zero() if $self->_sa()->is_zero($sa_result);

        return $self->_wrap_sa_result($sa_result, %slot_results);
    }

    # on_complete() delegates to each annotation-layer semiring and to SA.
    # Threads TI result to SA via set_type_context so SA actions can read
    # type annotations.
    # If any component returns zero, the whole result is zero.
    method on_complete($ctx, $rule_name, $alt_idx, $pos, $origin, $on_epoch_commit = undef) {
        return $self->zero() if $ctx->is_zero();

        # Run annotation-layer semirings; collect slot results
        my %slot_results;
        my $ti_result_tag_hash;
        for my $sr ($self->_annotation_semirings()) {
            my $slot = $sr->slot_name();
            my $val;
            # TI (#707): pass the shared Context directly so TI's on_complete
            # can walk annotations->{type} from children and return a tag hash.
            if ($slot eq 'type') {
                $val = $ctx;
            } else {
                $val = $ctx->annotations()->{$slot} // $sr->one();
            }
            my $result = $sr->on_complete($val, $rule_name, $alt_idx, $pos, $origin, $on_epoch_commit);
            return $self->zero() if $sr->is_zero($result);
            if ($slot eq 'type') {
                # TI's on_complete now returns a tag hash directly (#707).
                # Store it as annotations->{type} on the shared Context.
                $slot_results{type} = $result;
                $ti_result_tag_hash = $result;
            } else {
                $slot_results{$slot} = $result;
            }
        }

        # Thread TI result to SA before SA runs so action methods can read type info.
        # The bridge (set_type_context / current_type_context) is still needed because
        # SA actions run BEFORE FilterComposite overlays the type annotation (#708 will
        # eliminate on_complete and remove the bridge entirely).
        # Wrap the tag hash in a Context so set_type_context receives a Context object.
        if (defined $ti_result_tag_hash && $self->_sa()->can('set_type_context')) {
            my $ti_ctx_wrapper = Chalk::Bootstrap::Context->new(
                focus    => $ti_result_tag_hash,
                children => [],
                position => 0,
                rule     => undef,
            );
            $self->_sa()->set_type_context($ti_ctx_wrapper);
        }

        my $sa_result = $self->_sa()->on_complete($ctx, $rule_name, $alt_idx, $pos, $origin, $on_epoch_commit);
        return $self->zero() if $self->_sa()->is_zero($sa_result);

        return $self->_wrap_sa_result($sa_result, %slot_results);
    }

    # on_skip_optional() delegates to each annotation-layer semiring and to SA.
    # Semirings without on_skip_optional fall back to multiply(value, one()).
    method on_skip_optional($ctx, $rule_name, $alt_idx, $pos, $symbol_name) {
        return $self->zero() if $ctx->is_zero();

        my %slot_results;
        for my $sr ($self->_annotation_semirings()) {
            my $slot = $sr->slot_name();
            my $val;
            # TI (#707): pass the shared Context directly.
            if ($slot eq 'type') {
                $val = $ctx;
            } else {
                $val = $ctx->annotations()->{$slot} // $sr->one();
            }
            my $result;
            if ($sr->can('on_skip_optional')) {
                $result = $sr->on_skip_optional($val, $rule_name, $alt_idx, $pos, $symbol_name);
            } else {
                # TI (#707): on_skip_optional falls back to on_complete-style passthrough.
                # For the type slot, use TI's on_complete with an empty rule context.
                if ($slot eq 'type') {
                    $result = $sr->on_complete($val, $rule_name, $alt_idx, $pos, 0);
                } else {
                    $result = $sr->multiply($val, $sr->one());
                }
            }
            return $self->zero() if $sr->is_zero($result);
            if ($slot eq 'type') {
                # TI's result is a tag hash directly (#707).
                $slot_results{type} = $result;
            } else {
                $slot_results{$slot} = $result;
            }
        }

        my $sa_result;
        if ($self->_sa()->can('on_skip_optional')) {
            $sa_result = $self->_sa()->on_skip_optional($ctx, $rule_name, $alt_idx, $pos, $symbol_name);
        } else {
            $sa_result = $self->_sa()->multiply($ctx, $self->_sa()->one());
        }
        return $self->zero() if $self->_sa()->is_zero($sa_result);

        return $self->_wrap_sa_result($sa_result, %slot_results);
    }

    # should_scan() delegates to ALL component semirings (not just annotation-layer).
    # First-false short-circuit: if ANY component returns false, return false.
    # This allows any semiring to veto a scan before on_scan is called.
    # Each semiring receives its slot value (or the full Context for TI/SA).
    method should_scan($ctx, $rule_name, $alt_idx, $pos, $matched_text, $is_predicted) {
        for my $sr ($semirings->@*) {
            my $val;
            if (blessed($sr) && $sr->can('slot_name') && defined $sr->slot_name()) {
                my $slot = $sr->slot_name();
                if ($slot eq 'type') {
                    # TI (#707): pass the shared Context directly so TI's should_scan
                    # can walk annotations->{type} for call_symbol and other tags.
                    $val = $ctx;
                } else {
                    $val = $ctx->annotations()->{$slot} // $sr->one();
                }
            } else {
                # SA and non-annotation semirings receive the full Context
                $val = $ctx;
            }
            return false unless $sr->should_scan(
                $val, $rule_name, $alt_idx, $pos, $matched_text, $is_predicted
            );
        }
        return true;
    }
}
