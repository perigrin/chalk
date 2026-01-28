# ABOUTME: Longest match semiring for disambiguating between alternative parses
# ABOUTME: Prefers parses that consume more input, resolving grammar ambiguities

use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;

class Chalk::Semiring::LongestMatchElement :isa(Chalk::Element) {
    field $valid :param :reader = 1;
    field $start_pos :param :reader = 0;
    field $end_pos :param :reader = 0;
    field $semiring_add_id :param :reader = undef;
    field $semiring_mul_id :param :reader = undef;

    ADJUST {
        # Identity elements are self-referential
        $semiring_add_id //= $self;
        $semiring_mul_id //= $self;
    }

    method span() {
        return $end_pos - $start_pos;
    }

    method add($other, $swap = undef) {
        # Choose between alternative parses - prefer longest match
        return $self unless defined $other;
        return $self unless ref($other) && $other->can('valid');

        # If self is invalid (add_id), return other
        return $other if !$valid;

        # If other is invalid, return self
        return $self if !$other->valid;

        # Both valid - prefer the one with longer span
        my $self_span = $self->span;
        my $other_span = $other->span;

        if ($other_span > $self_span) {
            return $other;
        }

        # Prefer self (first alternative) when spans are equal
        return $self;
    }

    method multiply($other, $swap = undef) {
        return $self unless defined $other;
        return $self unless ref($other) && $other->can('valid');

        # If either is invalid, return cached add_id
        if (!$valid || !$other->valid) {
            return $semiring_add_id;
        }

        # Combine spans
        my $new_start = $start_pos < $other->start_pos ? $start_pos : $other->start_pos;
        my $new_end = $end_pos > $other->end_pos ? $end_pos : $other->end_pos;

        # Handle initial identity elements (both 0)
        if ($start_pos == 0 && $end_pos == 0) {
            $new_start = $other->start_pos;
            $new_end = $other->end_pos;
        } elsif ($other->start_pos == 0 && $other->end_pos == 0) {
            $new_start = $start_pos;
            $new_end = $end_pos;
        }

        return Chalk::Semiring::LongestMatchElement->new(
            valid => 1,
            start_pos => $new_start,
            end_pos => $new_end,
            semiring_add_id => $semiring_add_id,
            semiring_mul_id => $semiring_mul_id
        );
    }

    method equals($other, $swap = undef) {
        return 0 unless defined $other;
        return 0 unless ref($other) eq ref($self);
        return $valid == $other->valid && $start_pos == $other->start_pos && $end_pos == $other->end_pos;
    }

    method score() {
        return $valid ? $self->span : 0;
    }

    method to_string(@args) {
        return $valid ? "span[$start_pos,$end_pos]" : "invalid";
    }
}

class Chalk::Semiring::LongestMatch :isa(Chalk::Semiring) {
    field $mul_id :reader;
    field $add_id :reader;

    ADJUST {
        # Don't pass semiring_add_id/mul_id - will be self-referential
        $add_id = Chalk::Semiring::LongestMatchElement->new(valid => 0);
        $mul_id = Chalk::Semiring::LongestMatchElement->new(valid => 1);
    }

    method zero() {
        return $add_id;
    }

    method one() {
        return $mul_id;
    }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef) {
        return Chalk::Semiring::LongestMatchElement->new(
            valid => 1,
            start_pos => $start_pos,
            end_pos => $end_pos,
            semiring_add_id => $add_id,
            semiring_mul_id => $mul_id
        );
    }

    method multiply($x, $y) {
        return $x->multiply($y);
    }

    method plus($x, $y) {
        return $x->add($y);
    }

    method on_scan($item, $element, $pos, $matched_value, $pattern_name = undef) {
        my $match_length = length($matched_value // '');

        my $terminal_element = Chalk::Semiring::LongestMatchElement->new(
            valid => 1,
            start_pos => $pos,
            end_pos => $pos + $match_length,
            semiring_add_id => $add_id,
            semiring_mul_id => $mul_id
        );

        return $element->multiply($terminal_element);
    }

    method on_complete($completed_item, $completed_element, $metadata_element = undef) {
        return $completed_element;
    }
}

1;
