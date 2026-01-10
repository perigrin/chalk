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
        # CONTRACT: Return $self or $other directly (not copies) to enable
        # Composite::add() reference equality checks for consensus detection
        my $result_value = $value || $other->value;

        # Return original reference when it matches the result
        return $self if $value == $result_value;
        return $other if $other->value == $result_value;

        # Both false - create new (should be rare, but handle it)
        return Chalk::Semiring::BooleanElement->new(value => $result_value);
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

    # Keywords from grammar/chalk.bnf line 65
    field $keywords :reader = {
        map { $_ => 1 } qw(
            class field if unless elsif else while until for foreach
            return last next redo my our state use no require
            and or not eq ne lt gt le ge cmp
        )
    };

    method on_scan($item, $element, $pos, $matched_value, $pattern_name = undef) {
        # Reject keywords when they appear as identifiers
        my $is_identifier = defined($pattern_name) && $pattern_name eq 'IDENTIFIER';
        if ($is_identifier && defined($matched_value) && exists $keywords->{$matched_value}) {
            return $add_id;  # Return 0 (invalid parse)
        }
        # Otherwise return element unchanged
        return $element;
    }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef) {
        # All rules start as true (1) - they exist and can be used
        # Boolean semiring ignores positions and matched_value
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
