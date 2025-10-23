# ABOUTME: Sea of Nodes IR node representation for Chalk compiler
# ABOUTME: Represents a single node in the IR graph with operation type, inputs, and attributes
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::IR::Node {
    field $id         :param :reader;
    field $op         :param :reader;
    field $inputs     :param :reader;
    field $attributes :param :reader;

    method to_hash() {
        return {
            id         => $id,
            op         => $op,
            inputs     => $inputs,
            attributes => $attributes,
        };
    }

    method peephole($graph) {
        # Peephole optimization for constant folding
        # Check if this is an arithmetic operation with constant operands
        if ($op eq 'Add' || $op eq 'Multiply' || $op eq 'Subtract' || $op eq 'Divide') {
            my $left  = $attributes->{left};
            my $right = $attributes->{right};

            # Both operands must be constants for folding
            my $left_is_const = 0;
            if (defined($left)) {
                if ($left->{op} eq 'Constant') {
                    $left_is_const = 1;
                }
            }
            my $right_is_const = 0;
            if (defined($right)) {
                if ($right->{op} eq 'Constant') {
                    $right_is_const = 1;
                }
            }
            if ($left_is_const) {
                if ($right_is_const) {
                    my $left_val  = $left->{value};
                    my $right_val = $right->{value};
                    my $result;

                # Compute the result based on operation
                if ($op eq 'Add') {
                    $result = $left_val + $right_val;
                }
                elsif ($op eq 'Multiply') {
                    $result = $left_val * $right_val;
                }
                elsif ($op eq 'Subtract') {
                    $result = $left_val - $right_val;
                }
                elsif ($op eq 'Divide') {
                    # Avoid division by zero
                    return $self if $right_val == 0;
                    $result = int($left_val / $right_val);  # Integer division
                }

                # Return a new Constant node with the folded result
                return Chalk::IR::Node->new(
                    id         => $id,  # Reuse the same ID
                    op         => 'Constant',
                    inputs     => $inputs,
                    attributes => {
                        value => $result,
                        type  => 'Int',
                    }
                );
                }
            }
        }

        # Check if this is a comparison operation with constant operands
        if ($op eq 'GT' || $op eq 'LT' || $op eq 'EQ' || $op eq 'NE' || $op eq 'LE' || $op eq 'GE') {
            my $left  = $attributes->{left};
            my $right = $attributes->{right};

            # Both operands must be constants for folding
            my $left_is_const = 0;
            if (defined($left)) {
                if ($left->{op} eq 'Constant') {
                    $left_is_const = 1;
                }
            }
            my $right_is_const = 0;
            if (defined($right)) {
                if ($right->{op} eq 'Constant') {
                    $right_is_const = 1;
                }
            }
            if ($left_is_const) {
                if ($right_is_const) {
                    my $left_val  = $left->{value};
                    my $right_val = $right->{value};
                    my $result;

                    # Compute the result based on comparison operation
                    if ($op eq 'GT') {
                        $result = $left_val > $right_val ? 1 : 0;
                    }
                    elsif ($op eq 'LT') {
                        $result = $left_val < $right_val ? 1 : 0;
                    }
                    elsif ($op eq 'EQ') {
                        $result = $left_val == $right_val ? 1 : 0;
                    }
                    elsif ($op eq 'NE') {
                        $result = $left_val != $right_val ? 1 : 0;
                    }
                    elsif ($op eq 'LE') {
                        $result = $left_val <= $right_val ? 1 : 0;
                    }
                    elsif ($op eq 'GE') {
                        $result = $left_val >= $right_val ? 1 : 0;
                    }

                    # Return a new Constant node with the folded result (1 or 0)
                    return Chalk::IR::Node->new(
                        id         => $id,  # Reuse the same ID
                        op         => 'Constant',
                        inputs     => $inputs,
                        attributes => {
                            value => $result,
                            type  => 'Int',
                        }
                    );
                }
            }
        }

        # Load nodes can be optimized if they reference a Store with a constant value
        if ($op eq 'Load') {
            my $store_id = $attributes->{store_id};
            if (defined($store_id)) {
                my $store_node = $graph->get_node($store_id);
                my $is_store = 0;
                if (defined($store_node)) {
                    if ($store_node->op eq 'Store') {
                        $is_store = 1;
                    }
                }
                if ($is_store) {
                    my $value_ref = $store_node->attributes->{value};
                    my $is_const = 0;
                    if (defined($value_ref)) {
                        if ($value_ref->{op} eq 'Constant') {
                            $is_const = 1;
                        }
                    }
                    # If the stored value is a constant, fold the Load to that constant
                    if ($is_const) {
                        return Chalk::IR::Node->new(
                            id         => $id,
                            op         => 'Constant',
                            inputs     => $inputs,
                            attributes => {
                                value => $value_ref->{value},
                                type  => $value_ref->{type},
                            }
                        );
                    }
                }
            }
        }

        # No optimization possible, return self
        return $self;
    }
}

1;
