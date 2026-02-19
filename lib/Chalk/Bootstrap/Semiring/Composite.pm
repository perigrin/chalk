# ABOUTME: N-ary composite semiring running multiple semirings together as staged filters.
# ABOUTME: Values are N-tuples, is_zero returns true if ANY component is zero.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::Semiring::Composite {
    field $semirings :param :reader;  # arrayref of semirings

    # Shim: unwrap arrayref returns from semirings migrated to the
    # FilterComposite convention. A single-element arrayref [$value] unwraps to
    # $value. A multi-element arrayref signals that the semiring produced
    # multiple survivors, which requires FilterComposite (Phase 3) and is not
    # supported here. Plain scalar returns (not yet migrated semirings) pass
    # through unchanged.
    sub _unwrap_add_result($result, $semiring_idx) {
        return $result unless ref($result) eq 'ARRAY';
        if ($result->@* == 1) {
            return $result->[0];
        }
        if ($result->@* == 0) {
            # Zero survivors: semiring rejected both alternatives.
            # Return undef so is_zero catches it downstream.
            return;
        }
        die "Multiple survivors from semiring $semiring_idx add() — "
            . "requires FilterComposite (Phase 3)";
    }

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

    # Determine if two semiring values are "the same" for preference detection.
    # For references (Context objects, hashrefs): use object identity.
    # For scalars (integers, strings): use numeric/string equality.
    # Two values that are "the same" mean the semiring has no preference.
    sub _same_value($a, $b) {
        return false unless defined $a && defined $b;
        if (ref($a) && ref($b)) {
            return refaddr($a) == refaddr($b);
        }
        if (!ref($a) && !ref($b)) {
            return $a == $b;
        }
        return false;
    }

    method add($left, $right) {
        # For each semiring, detect whether it expresses a preference between
        # the two alternatives. A preference is expressed either via the legacy
        # selects_alternative() protocol or (for migrated semirings) by add()
        # returning a value that matches exactly one of its inputs but not the other.
        #
        # When a preference is detected, the whole tuple for the winning side
        # is returned: every semiring sees add(winner[i], winner[i]), ensuring
        # SemanticAction never receives two different alternatives.
        for my $i (0 .. $semirings->$#*) {
            my $li = $left->[$i];
            my $ri = $right->[$i];

            # Legacy protocol: semiring implements selects_alternative()
            if ($semirings->[$i]->can('selects_alternative')) {
                my $pref = $semirings->[$i]->selects_alternative($li, $ri);
                if (defined $pref) {
                    my $chosen = $pref eq 'left' ? $left : $right;
                    return [ map {
                        _unwrap_add_result($semirings->[$_]->add($chosen->[$_], $chosen->[$_]), $_)
                    } 0 .. $semirings->$#* ];
                }
                # No preference from this semiring — try next
                next;
            }

            # Migrated protocol: call add() and check result identity.
            #
            # Two cases where a semiring expresses a preference:
            #
            # Case A: Asymmetric inputs (li != ri).
            #   The semiring picks one side: result equals exactly one of {li, ri}.
            #
            # Case B: Identical inputs (li == ri) that are NOT the semiring's
            #   identity element (one()). This handles Structural's identical-tag
            #   tie-breakers (both is_list, both is_call+deref, both is_binop, etc.):
            #   when two alternatives have the same structural tags but differ in
            #   other semirings (Precedence, SemanticAction), Structural picks left
            #   to break the tie deterministically.
            #   We exclude the identity element to avoid false-positives from
            #   semirings like Boolean that always return true (= their one()).
            if (_same_value($li, $ri)) {
                my $one = $semirings->[$i]->one();
                if (!_same_value($li, $one)) {
                    # Non-trivial identical inputs: pick left tuple to break tie.
                    return [ map {
                        _unwrap_add_result($semirings->[$_]->add($left->[$_], $left->[$_]), $_)
                    } 0 .. $semirings->$#* ];
                }
                # Trivial identical inputs (both equal one()): no preference, skip.
                next;
            }

            my $result = _unwrap_add_result($semirings->[$i]->add($li, $ri), $i);

            if (_same_value($result, $li) && !_same_value($result, $ri)) {
                # Semiring prefers left
                return [ map {
                    _unwrap_add_result($semirings->[$_]->add($left->[$_], $left->[$_]), $_)
                } 0 .. $semirings->$#* ];
            }
            if (_same_value($result, $ri) && !_same_value($result, $li)) {
                # Semiring prefers right
                return [ map {
                    _unwrap_add_result($semirings->[$_]->add($right->[$_], $right->[$_]), $_)
                } 0 .. $semirings->$#* ];
            }

            # Result equals neither (synthesized merge) or equals both (no distinction).
            # No preference detected — continue to next semiring.
        }

        # No semiring expressed a preference — independent merge of all components.
        return [ map {
            _unwrap_add_result($semirings->[$_]->add($left->[$_], $right->[$_]), $_)
        } 0 .. $semirings->$#* ];
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
