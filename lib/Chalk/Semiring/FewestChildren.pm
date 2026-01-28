# ABOUTME: Fewest children semiring for disambiguating between alternative parses
# ABOUTME: Prefers parses with fewer top-level children (more cohesive structure)

use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;

class Chalk::Semiring::FewestChildrenElement :isa(Chalk::Element) {
    field $valid :param :reader = 1;
    field $child_count :param :reader = 0;
    field $semiring_add_id :param :reader = undef;
    field $semiring_mul_id :param :reader = undef;

    ADJUST {
        # Identity elements are self-referential
        $semiring_add_id //= $self;
        $semiring_mul_id //= $self;
    }

    method add($other, $swap = undef) {
        return $self unless defined $other;
        return $self unless ref($other) && $other->can('valid');

        # If self is invalid, return other
        return $other if !$valid;

        # If other is invalid, return self
        return $self if !$other->valid;

        # Both valid - prefer FEWER children (more cohesive parse)
        if ($other->child_count < $child_count) {
            return $other;
        }

        return $self;
    }

    method multiply($other, $swap = undef) {
        return $self unless defined $other;
        return $self unless ref($other) && $other->can('valid');

        if (!$valid || !$other->valid) {
            return $semiring_add_id;
        }

        # Sum children
        return Chalk::Semiring::FewestChildrenElement->new(
            valid => 1,
            child_count => $child_count + $other->child_count,
            semiring_add_id => $semiring_add_id,
            semiring_mul_id => $semiring_mul_id
        );
    }

    method equals($other, $swap = undef) {
        return 0 unless defined $other;
        return 0 unless ref($other) eq ref($self);
        return $valid == $other->valid && $child_count == $other->child_count;
    }

    method score() {
        return $valid ? 1 : 0;
    }

    method to_string(@args) {
        return $valid ? "children:$child_count" : "invalid";
    }
}

class Chalk::Semiring::FewestChildren :isa(Chalk::Semiring) {
    field $mul_id :reader;
    field $add_id :reader;

    ADJUST {
        # Don't pass semiring_add_id/mul_id - will be self-referential
        $add_id = Chalk::Semiring::FewestChildrenElement->new(valid => 0);
        $mul_id = Chalk::Semiring::FewestChildrenElement->new(valid => 1);
    }

    method zero() { return $add_id; }
    method one() { return $mul_id; }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef) {
        return Chalk::Semiring::FewestChildrenElement->new(
            valid => 1,
            child_count => 0,
            semiring_add_id => $add_id,
            semiring_mul_id => $mul_id
        );
    }

    method multiply($x, $y) { return $x->multiply($y); }
    method plus($x, $y) { return $x->add($y); }

    method on_scan($item, $element, $pos, $matched_value, $pattern_name = undef) {
        # Each terminal adds 1 to count
        my $terminal = Chalk::Semiring::FewestChildrenElement->new(
            valid => 1,
            child_count => 1,
            semiring_add_id => $add_id,
            semiring_mul_id => $mul_id
        );
        return $element->multiply($terminal);
    }

    method on_complete($completed_item, $completed_element, $metadata_element = undef) {
        return $completed_element;
    }
}

1;
