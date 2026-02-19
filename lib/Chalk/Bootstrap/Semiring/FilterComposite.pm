# ABOUTME: N-ary FilterComposite semiring running multiple semirings together as staged filters.
# ABOUTME: Values are N-tuples; add() uses _filter_compare to pick the winning tuple.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::Semiring::FilterComposite {
    field $semirings :param :reader;  # arrayref of semirings

    method zero() {
        return [ map { $_->zero() } $semirings->@* ];
    }

    method one() {
        return [ map { $_->one() } $semirings->@* ];
    }

    # Staged filter: ANY component zero → whole tuple is zero
    method is_zero($value) {
        for my $i (0 .. $semirings->$#*) {
            return true if $semirings->[$i]->is_zero($value->[$i]);
        }
        return false;
    }

    method multiply($left, $right) {
        return [ map { $semirings->[$_]->multiply($left->[$_], $right->[$_]) } 0 .. $semirings->$#* ];
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
        for my $i (0 .. $semirings->$#*) {
            my $li = $left->[$i];
            my $ri = $right->[$i];
            my $semiring = $semirings->[$i];

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

    method add($left, $right) {
        # Zero handling: if ANY component of left is zero, return right (and vice versa).
        for my $i (0 .. $semirings->$#*) {
            return $right if $semirings->[$i]->is_zero($left->[$i]);
            return $left  if $semirings->[$i]->is_zero($right->[$i]);
        }

        # Determine which tuple wins by scanning for semiring preferences.
        my $verdict = $self->_filter_compare($left, $right);

        if ($verdict eq 'right_loses') {
            return $left;
        }
        if ($verdict eq 'left_loses') {
            return $right;
        }

        # No semiring expressed a preference: deterministic tie-break picks left.
        return $left;
    }

    # Delegate on_scan to each component with its own slice of the value
    method on_scan($item, $alt_idx, $pos, $matched_text) {
        my @results;
        for my $i (0 .. $semirings->$#*) {
            my $component_item = { %$item, value => $item->{value}->[$i] };
            push @results, $semirings->[$i]->on_scan($component_item, $alt_idx, $pos, $matched_text);
        }
        return \@results;
    }

    # Delegate on_complete to each component with its own slice of the value
    method on_complete($item, $alt_idx, $pos) {
        my @results;
        for my $i (0 .. $semirings->$#*) {
            my $component_item = { %$item, value => $item->{value}->[$i] };
            push @results, $semirings->[$i]->on_complete($component_item, $alt_idx, $pos);
        }
        return \@results;
    }
}
