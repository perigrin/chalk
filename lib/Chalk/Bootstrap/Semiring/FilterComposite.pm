# ABOUTME: N-ary FilterComposite semiring running multiple semirings together as staged filters.
# ABOUTME: Values are N-tuples; add() uses _filter_compare to pick the winning tuple.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::Semiring::FilterComposite {
    field $semirings :param :reader;  # arrayref of semirings

    # Clear hash-cons caches in all component semirings that support it.
    # Called between file parses to prevent unbounded memory growth.
    method reset_cache() {
        for my $sr ($semirings->@*) {
            $sr->reset_cache() if $sr->can('reset_cache');
        }
    }

    method zero() {
        my @z;
        for my $sr ($semirings->@*) {
            push @z, $sr->zero();
        }
        return \@z;
    }

    method one() {
        my @o;
        for my $sr ($semirings->@*) {
            push @o, $sr->one();
        }
        return \@o;
    }

    # Staged filter: ANY component zero → whole tuple is zero
    method is_zero($value) {
        for my $i (0 .. scalar($semirings->@*) - 1) {
            my $sr = $semirings->[$i];
            my $vi = $value->[$i];
            return true if $sr->is_zero($vi);
        }
        return false;
    }

    method multiply($left, $right) {
        my @result;
        for my $idx (0 .. scalar($semirings->@*) - 1) {
            my $sr = $semirings->[$idx];
            my $lr = $left->[$idx];
            my $rr = $right->[$idx];
            my $mr = $sr->multiply($lr, $rr);
            push @result, $mr;
        }
        # Annihilator: if any component multiply returns zero, the whole tuple is zero.
        for my $i (0 .. scalar($semirings->@*) - 1) {
            my $sr = $semirings->[$i];
            my $ri = $result[$i];
            return $self->zero() if $sr->is_zero($ri);
        }
        return \@result;
    }

    # _filter_compare: scan each semiring for a preference between left and right.
    #
    # Semirings are checked in priority order. The FIRST semiring that expresses a
    # clear preference determines the winner — subsequent semirings are not consulted.
    # This matches the ordered-filter semantics: earlier semirings have higher priority.
    #
    # For each semiring i, calls $semiring->add($li, $ri) and inspects the result:
    #   - If the result matches $li but not $ri → this semiring prefers left ('right_loses')
    #   - If the result matches $ri but not $li → this semiring prefers right ('left_loses')
    #   - If result matches both or neither → no preference, try next semiring
    #
    # Identity comparison: scalars compare numerically; refs compare by refaddr.
    # Semiring add() returns are normalized to arrayrefs for uniform handling.
    #
    # Returns: 'right_loses' | 'left_loses' | 'neither'
    method _filter_compare($left, $right) {
        for my $i (0 .. scalar($semirings->@*) - 1) {
            my $semiring = $semirings->[$i];
            my $li = $left->[$i];
            my $ri = $right->[$i];

            # Skip identity: same value means this semiring cannot distinguish.
            my $same;
            if (ref($li) && ref($ri)) {
                $same = refaddr($li) == refaddr($ri);
            } elsif (!ref($li) && !ref($ri)) {
                $same = $li == $ri;
            } else {
                $same = false;
            }
            next if $same;

            # Invoke semiring add() and normalize result to arrayref.
            # Semirings using the legacy scalar protocol (Boolean, Structural)
            # return bare scalars; we wrap them so the comparison below is uniform.
            my $result = $semiring->add($li, $ri);
            $result = [$result] unless ref($result) eq 'ARRAY';

            # Empty result: semiring rejects both alternatives (should not happen
            # here because zeros are filtered before _filter_compare is called,
            # but guard anyway).
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
            # (This should not happen with well-designed filter semirings, but we
            # treat it gracefully rather than dying.)
            next unless $r_eq_left || $r_eq_right;

            # First semiring to express a preference wins. Return immediately.
            return $r_eq_left ? 'right_loses' : 'left_loses';
        }

        return 'neither';
    }

    # add() returns a single winning tuple, not a survivor list.
    #
    # The design doc specifies survivor lists where multiple alternatives can
    # survive, with an end-of-parse assertion catching genuine ambiguities.
    # This implementation uses single-tuple representation because the Earley
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
        # Zero handling: if ANY component of left is zero, return right (and vice versa).
        for my $i (0 .. scalar($semirings->@*) - 1) {
            my $sr = $semirings->[$i];
            my $li = $left->[$i];
            my $ri = $right->[$i];
            return $right if $sr->is_zero($li);
            return $left  if $sr->is_zero($ri);
        }

        # Determine which tuple wins by scanning for semiring preferences.
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

        # Post-merge hook: allow semirings to transfer side-table state from
        # loser to winner. This fixes the Earley stale-value merge problem
        # where cfg_state updates are lost when add() picks the older value.
        for my $i (0 .. scalar($semirings->@*) - 1) {
            my $sr = $semirings->[$i];
            if ($sr->can('on_merge')) {
                my $wi = $winner->[$i];
                my $lo = $loser->[$i];
                $sr->on_merge($wi, $lo);
            }
        }

        return $winner;
    }

    # Delegate on_scan to each component with its own slice of the value.
    # If any component returns zero, the whole tuple is zero.
    method on_scan($value, $rule_name, $alt_idx, $pos, $matched_text) {
        my @results;
        for my $i (0 .. scalar($semirings->@*) - 1) {
            my $sr = $semirings->[$i];
            my $r = $sr->on_scan($value->[$i], $rule_name, $alt_idx, $pos, $matched_text);
            return $self->zero() if $sr->is_zero($r);
            push @results, $r;
        }
        return \@results;
    }

    # Delegate on_complete to each component with its own slice of the value.
    # If any component returns zero, the whole tuple is zero.
    # Threads TypeInference result (index 2) to SemanticAction (index 4)
    # via set_type_context so SA actions can read type annotations.
    method on_complete($value, $rule_name, $alt_idx, $pos, $origin, $on_epoch_commit = undef) {
        my @results;
        my $ti_result;
        for my $i (0 .. scalar($semirings->@*) - 1) {
            my $sr = $semirings->[$i];
            # Thread TI result to SA: indices 2=TI, 4=SA match pipeline
            # construction order in TestPipeline/build_perl_concise_parser.
            if ($i == 4 && defined $ti_result
                    && $sr->can('set_type_context')) {
                $sr->set_type_context($ti_result);
            }
            my $r = $sr->on_complete($value->[$i], $rule_name, $alt_idx, $pos, $origin, $on_epoch_commit);
            return $self->zero() if $sr->is_zero($r);
            push @results, $r;
            # Capture TI result after it completes
            $ti_result = $r if $i == 2;
        }
        return \@results;
    }

    # Delegate on_skip_optional to each component.
    # Semirings with on_skip_optional get the placeholder path;
    # others fall back to multiply(value, one()) which is identity.
    method on_skip_optional($value, $rule_name, $alt_idx, $pos, $symbol_name) {
        my @results;
        for my $i (0 .. scalar($semirings->@*) - 1) {
            my $sr = $semirings->[$i];
            my $r;
            if ($sr->can('on_skip_optional')) {
                $r = $sr->on_skip_optional($value->[$i], $rule_name, $alt_idx, $pos, $symbol_name);
            } else {
                $r = $sr->multiply($value->[$i], $sr->one());
            }
            return $self->zero() if $sr->is_zero($r);
            push @results, $r;
        }
        return \@results;
    }

    # should_scan: gate for scan operation, called after regex match succeeds.
    # First-false short-circuit: if ANY component returns false, return false.
    # This allows any semiring to veto a scan before on_scan is called.
    method should_scan($value, $rule_name, $alt_idx, $pos, $matched_text, $is_predicted) {
        for my $i (0 .. scalar($semirings->@*) - 1) {
            my $sr = $semirings->[$i];
            return false unless $sr->should_scan(
                $value->[$i], $rule_name, $alt_idx, $pos, $matched_text, $is_predicted
            );
        }
        return true;
    }
}
