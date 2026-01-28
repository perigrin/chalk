# ABOUTME: Boolean semiring for fast parse validation without position tracking
# ABOUTME: Provides simple true/false parsing for syntax checking similar to perl -c
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;

class Chalk::Semiring::BooleanElement :isa(Chalk::Element) {
    field $value :param :reader;
    field $semiring_add_id :param :reader = undef;  # Cached add_id from parent
    field $semiring_mul_id :param :reader = undef;  # Cached mul_id from parent

    ADJUST {
        # Identity elements are self-referential
        $semiring_add_id //= $self;
        $semiring_mul_id //= $self;
    }

    method add( $other, $swap = undef ) {
        # Boolean OR for choice: either can succeed
        # CONTRACT: Return $self or $other directly (not copies) to enable
        # Composite::add() reference equality checks for consensus detection
        my $result_value = $value || $other->value;

        # INSTRUMENTATION: Log Boolean.add() decisions
        if ($ENV{DEBUG_PARSE_ALTERNATIVES}) {
            my $self_val = $value ? 1 : 0;
            my $other_val = $other->value ? 1 : 0;
            warn "[BOOLEAN.add] self=$self_val vs other=$other_val\n";
        }

        # Return original reference when it matches the result
        if ($value == $result_value) {
            if ($ENV{DEBUG_PARSE_ALTERNATIVES}) {
                warn "[BOOLEAN.add]   => Choosing SELF\n";
            }
            return $self;
        }
        if ($other->value == $result_value) {
            if ($ENV{DEBUG_PARSE_ALTERNATIVES}) {
                warn "[BOOLEAN.add]   => Choosing OTHER\n";
            }
            return $other;
        }

        # Both false - return cached add_id
        if ($ENV{DEBUG_PARSE_ALTERNATIVES}) {
            warn "[BOOLEAN.add]   => Both false, returning add_id\n";
        }
        return $semiring_add_id;
    }

    method multiply( $other, $swap = undef ) {
        # Boolean AND for sequence: both must succeed
        my $result_value = $value && $other->value;

        # Return cached add_id if result is false (avoids creating new add_id instances)
        return $semiring_add_id unless $result_value;

        # Return cached mul_id if result is true
        return $semiring_mul_id if $result_value;
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
    # Identity elements for Boolean algebra - self-referential via ADJUST
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
        if ($is_identifier && defined($matched_value)) {
            my $token_value = ref($matched_value) && $matched_value->can('value') ? $matched_value->value : $matched_value;
            if (exists $keywords->{$token_value}) {
                return $add_id;  # Return 0 (invalid parse)
            }
        }
        # Otherwise return element unchanged
        return $element;
    }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef) {
        # All rules start as true (1) - they exist and can be used
        # Return cached mul_id to avoid creating new instances
        return $mul_id;
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
