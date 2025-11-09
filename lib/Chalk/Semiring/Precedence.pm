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
    field $associativity :param :reader = undef;  # Associativity type: left, right, nonassoc, chained, chain/na

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
        return Chalk::Semiring::PrecedenceElement->new(valid => 0) if !$valid || !$other->valid;

        # Precedence validation: check if $other (right operand) has valid precedence
        # relative to $self (left context/current operator)

        # If either element has no operator info, allow it (non-operator elements)
        return Chalk::Semiring::PrecedenceElement->new(valid => 1)
            if !defined($operator) || !defined($other->operator);

        # Both have operators - validate based on precedence and associativity
        my $self_level = $precedence_level;
        my $other_level = $other->precedence_level;
        my $self_assoc = $associativity;
        my $other_assoc = $other->associativity;

        # Rule 1: Lower precedence (higher index) cannot nest inside higher precedence (lower index)
        if ($other_level > $self_level) {
            return Chalk::Semiring::PrecedenceElement->new(valid => 0);
        }

        # Rule 2: If different precedence levels, higher can nest in lower - valid
        if ($other_level < $self_level) {
            return Chalk::Semiring::PrecedenceElement->new(valid => 1);
        }

        # Same precedence level - check associativity rules
        # Rule 3: nonassoc operators cannot chain with themselves
        if (defined($self_assoc) && $self_assoc eq 'nonassoc') {
            # nonassoc operators at same level cannot chain
            if ($operator eq $other->operator) {
                return Chalk::Semiring::PrecedenceElement->new(valid => 0);
            }
        }

        # Rule 4: chained comparisons must maintain directional consistency
        if (defined($self_assoc) && $self_assoc eq 'chained') {
            # Determine direction of operators
            my $self_dir = _operator_direction($operator);
            my $other_dir = _operator_direction($other->operator);

            # If both have directions, they must match
            if (defined($self_dir) && defined($other_dir) && $self_dir ne $other_dir) {
                return Chalk::Semiring::PrecedenceElement->new(valid => 0);
            }
        }

        # Rule 5: chain/na allows chaining (like chained but context-dependent)
        # For now, treat same as chained - allow chaining
        if (defined($self_assoc) && $self_assoc eq 'chain/na') {
            # Allow chaining
            return Chalk::Semiring::PrecedenceElement->new(valid => 1);
        }

        # Rule 6: left and right associativity (existing behavior)
        # left: disallow equal precedence on right (already handled by "cannot be lower")
        # right: allow equal precedence on right (needs explicit check)
        # Default: valid
        return Chalk::Semiring::PrecedenceElement->new(valid => 1);
    }

    # Helper: Determine comparison operator direction
    sub _operator_direction {
        my ($op) = @_;
        # Use hash lookup to avoid < and > in regex patterns (confuses Chalk parser)
        my %ascending = ('<' => 1, '<=' => 1, 'lt' => 1, 'le' => 1);
        my %descending = ('>' => 1, '>=' => 1, 'gt' => 1, 'ge' => 1);
        return 'asc' if exists $ascending{$op};
        return 'desc' if exists $descending{$op};
        return undef;  # No direction (e.g., ==, !=)
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
        for my $i (0 .. $precedence_table->@* - 1) {
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

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef) {
        # Extract operator from rule if it's a binary operation
        # Pattern: E -> E OP E (3 elements in RHS)
        # Operator is at index 1 (middle position)

        my $rhs = $rule->rhs;
        my $operator = undef;
        my $prec_level = undef;
        my $assoc = undef;

        # Check if this looks like a binary operation rule
        if ($rhs->@* == 3) {
            my $candidate = $rhs->[1];  # Middle element

            # Check if this candidate is in our precedence table
            if (defined($candidate) && !ref($candidate)) {
                my $op_info = $self->lookup_operator($candidate);
                if ($op_info) {
                    $operator = $candidate;
                    $prec_level = $op_info->{level};
                    $assoc = $op_info->{assoc};
                }
            }
        }

        return Chalk::Semiring::PrecedenceElement->new(
            valid => 1,
            operator => $operator,
            precedence_level => $prec_level,
            associativity => $assoc
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
