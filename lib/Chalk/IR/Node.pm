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
            if (defined $left && defined $right &&
                $left->{op} eq 'Constant' && $right->{op} eq 'Constant') {

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

        # No optimization possible, return self
        return $self;
    }
}

1;
