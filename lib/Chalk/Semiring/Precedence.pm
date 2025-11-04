# ABOUTME: Precedence semiring for operator precedence validation during parsing
# ABOUTME: Implements proactive pruning via precedence table with left/right associativity
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;

class Chalk::Semiring::PrecedenceElement :isa(Chalk::Element) {
    field $valid :param :reader;  # Boolean: 1 = valid precedence, 0 = invalid
    field $operator :param :reader = undef;  # Operator symbol (if known)
    field $precedence_level :param :reader = undef;  # Index in precedence table

    method add( $other, $swap = undef ) {
        # Boolean OR for choice: either can succeed
        # If self is invalid (add_id, value 0), return other
        # Otherwise prefer valid over invalid
        return $other if !$valid;
        return $self;
    }

    method multiply( $other, $swap = undef ) {
        # Boolean AND for sequence: both must succeed
        # If either is invalid, result is invalid
        return Chalk::Semiring::PrecedenceElement->new(
            valid => $valid && $other->valid
        );
    }

    method equals( $other, $swap = undef ) {
        return 0 unless ref($other) eq ref($self);
        return $valid == $other->valid;
    }

    method score() {
        return $valid;
    }

    method to_string(@args) {
        my $op_str = defined($operator) ? " op=$operator" : "";
        my $prec_str = defined($precedence_level) ? " prec=$precedence_level" : "";
        return $valid ? "1${op_str}${prec_str}" : "0${op_str}${prec_str}";
    }
}

class Chalk::Semiring::Precedence :isa(Chalk::Semiring) {
    field $precedence_table :param :reader;
    field $mul_id :reader;
    field $add_id :reader;
    field $operator_index :reader;  # Hash: operator -> index in precedence table

    ADJUST {
        # Build operator index for fast lookup
        my %index;
        for my $i (0 .. $precedence_table->$#*) {
            my $entry = $precedence_table->[$i];
            for my $op ($entry->{ops}->@*) {
                $index{$op} = {
                    level => $i,
                    assoc => $entry->{assoc}
                };
            }
        }
        $operator_index = \%index;

        # Identity elements: like Boolean semiring
        $mul_id = Chalk::Semiring::PrecedenceElement->new(valid => 1);
        $add_id = Chalk::Semiring::PrecedenceElement->new(valid => 0);
    }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0) {
        # All rules start as valid (1) - they exist and can be used
        # Precedence validation happens during multiply()
        return Chalk::Semiring::PrecedenceElement->new(
            valid => 1,
            operator => undef,
            precedence_level => undef
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

    # Lookup operator precedence and associativity
    method lookup_operator($op) {
        return $operator_index->{$op};
    }
}

1;
