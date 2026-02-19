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

    method add($left, $right) {
        # Check if any component selects a preferred alternative.
        # When a preference is expressed, each component's add() receives
        # the preferred side as BOTH arguments, ensuring component-specific
        # merge logic still runs (e.g., SemanticAction's Context handling).
        for my $i (0 .. $semirings->$#*) {
            if ($semirings->[$i]->can('selects_alternative')) {
                my $pref = $semirings->[$i]->selects_alternative(
                    $left->[$i], $right->[$i],
                );
                if (defined $pref) {
                    my $chosen = $pref eq 'left' ? $left : $right;
                    return [ map {
                        _unwrap_add_result($semirings->[$_]->add($chosen->[$_], $chosen->[$_]), $_)
                    } 0 .. $semirings->$#* ];
                }
            }
        }

        # No preference: merge each component independently
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
