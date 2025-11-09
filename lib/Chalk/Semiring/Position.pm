# ABOUTME: Position semiring for tracking parse spans without SPPF complexity
# ABOUTME: Provides lightweight position tracking for incomplete parse detection

use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;

class Chalk::Semiring::PositionElement :isa(Chalk::Element) {
    field $start_pos :param :reader;
    field $end_pos   :param :reader;

    method add( $other, $swap = undef ) {
        # Choice: prefer whichever parse went further
        # If tied, prefer $self (arbitrary but consistent)
        return $end_pos >= $other->end_pos ? $self : $other;
    }

    method multiply( $other, $swap = undef ) {
        # Sequence: combine spans [self.start, other.end]
        return Chalk::Semiring::PositionElement->new(
            start_pos => $start_pos,
            end_pos   => $other->end_pos
        );
    }

    method equals( $other, $swap = undef ) {
        return 0 unless ref($other) eq ref($self);
        return $start_pos == $other->start_pos
            && $end_pos == $other->end_pos;
    }

    method score() {
        # For compatibility - return span length
        return $end_pos - $start_pos;
    }

    method to_string(@args) {
        return "[$start_pos,$end_pos]";
    }
}

class Chalk::Semiring::Position :isa(Chalk::Semiring) {
    # Identity elements
    field $mul_id :reader = Chalk::Semiring::PositionElement->new(
        start_pos => 0,
        end_pos   => 0
    );

    field $add_id :reader = Chalk::Semiring::PositionElement->new(
        start_pos => 0,
        end_pos   => 0
    );

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef) {
        return Chalk::Semiring::PositionElement->new(
            start_pos => $start_pos,
            end_pos   => $end_pos
        );
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
