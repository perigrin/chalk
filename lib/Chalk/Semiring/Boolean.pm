# ABOUTME: Boolean semiring for fast parse validation without position tracking
# ABOUTME: Provides simple true/false parsing for syntax checking similar to perl -c
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;

class Chalk::Semiring::BooleanElement :isa(Chalk::Element) {
    field $value :param :reader;

    method add( $other, $swap = undef ) {
        # Boolean OR for choice: either can succeed
        return Chalk::Semiring::BooleanElement->new(
            value => $value || $other->value
        );
    }

    method multiply( $other, $swap = undef ) {
        # Boolean AND for sequence: both must succeed
        return Chalk::Semiring::BooleanElement->new(
            value => $value && $other->value
        );
    }

    method equals( $other, $swap = undef ) {
        return 0 unless ref($other) eq ref($self);
        return $value == $other->value;
    }

    method score() {
        return $value;
    }

    method to_string(@args) {
        return $value ? '1' : '0';
    }
}

class Chalk::Semiring::Boolean :isa(Chalk::Semiring) {
    # Identity elements for Boolean algebra
    field $mul_id :reader = Chalk::Semiring::BooleanElement->new(value => 1);
    field $add_id :reader = Chalk::Semiring::BooleanElement->new(value => 0);

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0) {
        # All rules start as true (1) - they exist and can be used
        # Boolean semiring ignores positions
        return Chalk::Semiring::BooleanElement->new(value => 1);
    }

    method multiply($x, $y) {
        # For backward compatibility if called directly
        return $x->multiply($y);
    }

    method plus($x, $y) {
        # For backward compatibility if called directly
        return $x->add($y);
    }
}

1;
