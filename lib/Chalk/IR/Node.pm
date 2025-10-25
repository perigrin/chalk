# ABOUTME: Sea of Nodes IR node representation for Chalk compiler
# ABOUTME: Represents a single node in the IR graph with operation type, inputs, and attributes
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::IR::Node {
    field $id           :param :reader;
    field $op           :param :reader;
    field $inputs       :param :reader;
    field $attributes   :param :reader;
    field $derivation_id :param :reader = undef;

    method to_hash() {
        return {
            id           => $id,
            op           => $op,
            inputs       => $inputs,
            attributes   => $attributes,
            derivation_id => $derivation_id,
        };
    }

    # Helper: Check if an attribute represents a constant value
    sub _is_constant($attr) {
        return defined($attr) && $attr->{op} eq 'Constant';
    }

    # Helper: Check for integer overflow in arithmetic operations
    # Returns true if operation would overflow, false otherwise
    # Uses 64-bit signed integer bounds (common on modern systems)
    sub _would_overflow($op, $left, $right) {
        my $max_int = 9223372036854775807;   # 2^63 - 1
        my $min_int = -9223372036854775808;  # -2^63

        if ($op eq 'Add') {
            return 1 if $left > 0 && $right > 0 && $left > $max_int - $right;
            return 1 if $left < 0 && $right < 0 && $left < $min_int - $right;
        }
        elsif ($op eq 'Subtract') {
            return 1 if $left > 0 && $right < 0 && $left > $max_int + $right;
            return 1 if $left < 0 && $right > 0 && $left < $min_int + $right;
        }
        elsif ($op eq 'Multiply') {
            return 1 if $left != 0 && abs($right) > abs($max_int / $left);
        }
        return 0;
    }

    method peephole($graph) {
        # Peephole optimization for constant folding
        # Check if this is an arithmetic operation with constant operands
        if ($op eq 'Add' || $op eq 'Multiply' || $op eq 'Subtract' || $op eq 'Divide') {
            my $left  = $attributes->{left};
            my $right = $attributes->{right};

            # Both operands must be constants for folding
            if (_is_constant($left) && _is_constant($right)) {
                my $left_val  = $left->{value};
                my $right_val = $right->{value};

                # Skip optimization if it would overflow
                return $self if _would_overflow($op, $left_val, $right_val);

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
                    # Don't optimize division by zero - let it fail at runtime
                    return $self if $right_val == 0;
                    $result = int($left_val / $right_val);  # Integer division
                }

                # Return a new Constant node with the folded result
                return Chalk::IR::Node->new(
                    id            => $id,  # Reuse the same ID
                    op            => 'Constant',
                    inputs        => $inputs,
                    attributes    => {
                        value => $result,
                        type  => 'Int',
                    },
                    derivation_id => $derivation_id,
                );
            }
        }

        # Check if this is a comparison operation with constant operands
        if ($op eq 'GT' || $op eq 'LT' || $op eq 'EQ' || $op eq 'NE' || $op eq 'LE' || $op eq 'GE') {
            my $left  = $attributes->{left};
            my $right = $attributes->{right};

            # Both operands must be constants for folding
            if (_is_constant($left) && _is_constant($right)) {
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
                    id            => $id,  # Reuse the same ID
                    op            => 'Constant',
                    inputs        => $inputs,
                    attributes    => {
                        value => $result,
                        type  => 'Int',
                    },
                    derivation_id => $derivation_id,
                );
            }
        }

        # Load nodes can be optimized if they reference a Store with a constant value
        # ONLY if there are no intervening stores that might alias
        if ($op eq 'Load') {
            my $store_id = $attributes->{store_id};
            if (defined($store_id)) {
                my $store_node = $graph->get_node($store_id);
                if (defined($store_node) && $store_node->op eq 'Store') {
                    my $value_ref = $store_node->attributes->{value};
                    # If the stored value is a constant, check for intervening stores
                    if (_is_constant($value_ref)) {
                        # Conservative aliasing check: Check if any of the Load's inputs
                        # is a Store node that is NOT the store_id. If so, there's an
                        # intervening store that might alias.
                        for my $input_id ($inputs->@*) {
                            next unless defined($input_id);
                            next if $input_id eq $store_id;  # Skip the target store

                            my $input_node = $graph->get_node($input_id);
                            if (defined($input_node) && $input_node->op eq 'Store') {
                                # Found an intervening Store - don't optimize (conservative)
                                # This prevents incorrect optimization when stores might alias
                                return $self;
                            }
                        }

                        # Safe to optimize: No intervening Store nodes found
                        return Chalk::IR::Node->new(
                            id            => $id,
                            op            => 'Constant',
                            inputs        => $inputs,
                            attributes    => {
                                value => $value_ref->{value},
                                type  => $value_ref->{type},
                            },
                            derivation_id => $derivation_id,
                        );
                    }
                }
            }
        }

        # Chapter 6: Proj node optimization for constant If conditions
        if ($op eq 'Proj') {
            # Check if this Proj is from an If node
            if (scalar( $inputs->@* ) > 0) {
                my $parent_id = $inputs->[0];
                my $parent = $graph->get_node($parent_id);
                if (defined($parent) && $parent->op eq 'If') {
                    # Get the If node's condition
                    my $condition_attr = $parent->attributes->{condition};
                    if (defined($condition_attr) && $condition_attr->{op} eq 'Constant') {
                        my $cond_value = $condition_attr->{value};
                        my $proj_index = $attributes->{index};

                        # If condition is true (non-zero), index 0 is live, index 1 is dead
                        # If condition is false (zero), index 1 is live, index 0 is dead
                        my $is_live = ($cond_value) ? ($proj_index == 0) : ($proj_index == 1);

                        if ($is_live) {
                            # Live branch: pass through the If node's control input
                            if (scalar( $parent->inputs->@* ) > 0) {
                                my $ctrl_id = $parent->inputs->[0];
                                my $ctrl_node = $graph->get_node($ctrl_id);
                                if (defined($ctrl_node)) {
                                    return $ctrl_node;
                                }
                            }
                        } else {
                            # Dead branch: return ~Ctrl constant
                            return Chalk::IR::Node->new(
                                id            => $id,
                                op            => 'Constant',
                                inputs        => [],
                                attributes    => {
                                    value => '~Ctrl',
                                    type  => 'Control',
                                },
                                derivation_id => $derivation_id,
                            );
                        }
                    }
                }
            }
        }

        # Chapter 6: Region node collapse when only one input is live
        if ($op eq 'Region') {
            my @live_inputs;
            for my $input_id ($inputs->@*) {
                my $input_node = $graph->get_node($input_id);
                if (defined($input_node)) {
                    # Check if input is dead control (~Ctrl)
                    if ($input_node->op eq 'Constant' &&
                        defined($input_node->attributes->{value}) &&
                        $input_node->attributes->{value} eq '~Ctrl') {
                        # Skip dead input
                        next;
                    }
                    push @live_inputs, $input_id;
                }
            }

            # If only one live input, collapse to that input
            if (scalar( @live_inputs ) == 1) {
                my $live_id = $live_inputs[0];
                my $live_node = $graph->get_node($live_id);
                if (defined($live_node)) {
                    return $live_node;
                }
            }
        }

        # Chapter 6: Phi node simplification when one or more inputs are from dead control
        if ($op eq 'Phi') {
            my $region_id = $attributes->{region_id};
            if (defined($region_id)) {
                my $region = $graph->get_node($region_id);
                if (defined($region) && $region->op eq 'Region') {
                    my @region_inputs = $region->inputs->@*;

                    # Get alternatives from inputs array (skip first element which is region control)
                    # Standardized representation: inputs => [region_id, alt1, alt2, ...]
                    my @phi_inputs = $inputs->@*;
                    my @alternatives = @phi_inputs[1 .. $#phi_inputs];  # Skip region at index 0

                    # Find live alternatives (where corresponding Region input is not ~Ctrl)
                    my @live_values;
                    for my $i (0 .. $#region_inputs) {
                        my $ctrl_id = $region_inputs[$i];
                        my $ctrl_node = $graph->get_node($ctrl_id);

                        # Check if this control input is dead
                        my $is_dead = 0;
                        if (defined($ctrl_node)) {
                            if ($ctrl_node->op eq 'Constant' &&
                                defined($ctrl_node->attributes->{value}) &&
                                $ctrl_node->attributes->{value} eq '~Ctrl') {
                                $is_dead = 1;
                            }
                        }

                        # If control is live, keep this alternative
                        if (!$is_dead && $i < scalar( @alternatives )) {
                            push @live_values, $alternatives[$i];
                        }
                    }

                    # If only one live value, replace Phi with that value
                    if (scalar( @live_values ) == 1) {
                        my $value_id = $live_values[0];
                        my $value_node = $graph->get_node($value_id);
                        if (defined($value_node)) {
                            return $value_node;
                        }
                    }
                }
            }
        }

        # No optimization possible, return self
        return $self;
    }
}

1;
