# ABOUTME: Type validation pass for IR graphs
# ABOUTME: Validates type consistency across nodes and operations

use 5.42.0;
use experimental qw(class);
use utf8;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;
use Chalk::IR::Type::Union;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;

class Chalk::IR::TypeValidator {
    field $graph :param :reader;
    field $type_map :param :reader;

    # Validation results
    field $errors = [];

    # Validate the IR graph for type consistency
    # Returns: { valid => bool, errors => ArrayRef[String] }
    method validate() {
        $errors = [];

        # Visit all nodes in the graph
        for my $node_id (keys $graph->nodes->%*) {
            my $node = $graph->nodes->{$node_id};
            next unless defined $node;

            $self->_validate_node($node);
        }

        return {
            valid => (scalar($errors->@*) == 0),
            errors => [$errors->@*],  # Return copy
        };
    }

    # Validate a single node
    method _validate_node($node) {
        my $node_id = $node->id;
        my $op = $node->op;

        # Check that node has a type
        my $node_type = $type_map->{$node_id};
        unless (defined $node_type) {
            push $errors->@*, "Node $node_id (op=$op) has no type information";
            return;
        }

        # Validate based on operation type
        if ($op eq 'Add' || $op eq 'Subtract' || $op eq 'Multiply' || $op eq 'Divide') {
            $self->_validate_arithmetic($node);
        }
        elsif ($op eq 'StrConcat') {
            $self->_validate_string_op($node);
        }
        elsif ($op eq 'Phi') {
            $self->_validate_phi($node);
        }
        # Other operations don't need special validation for now
    }

    # Validate arithmetic operations have numeric operands
    method _validate_arithmetic($node) {
        return unless $node->can('inputs');
        my $inputs = $node->inputs;
        return unless defined $inputs;

        for my $input_id ($inputs->@*) {
            my $input_type = $type_map->{$input_id};
            next unless defined $input_type;

            # Check if type is numeric (Integer, Float, or Union containing them)
            unless ($self->_is_numeric_type($input_type)) {
                # In Perl, everything can coerce to a number, so this is a warning not error
                # We'll be permissive here - only error on Bottom types
                if ($input_type isa Chalk::IR::Type::Bottom) {
                    push $errors->@*, sprintf(
                        "Node %d (op=%s) has Bottom type operand at input %d",
                        $node->id, $node->op, $input_id
                    );
                }
            }
        }
    }

    # Validate string operations (very permissive in Perl)
    method _validate_string_op($node) {
        return unless $node->can('inputs');
        my $inputs = $node->inputs;
        return unless defined $inputs;

        # In Perl, everything is stringifiable, so we only check for Bottom
        for my $input_id ($inputs->@*) {
            my $input_type = $type_map->{$input_id};
            next unless defined $input_type;

            if ($input_type isa Chalk::IR::Type::Bottom) {
                push $errors->@*, sprintf(
                    "Node %d (op=%s) has Bottom type operand at input %d",
                    $node->id, $node->op, $input_id
                );
            }
        }
    }

    # Validate Phi nodes have compatible incoming types
    method _validate_phi($node) {
        return unless $node->can('inputs');
        my $inputs = $node->inputs;
        return unless defined $inputs;

        # Phi nodes: first input is control, rest are values
        my @value_inputs = $inputs->@[1..$inputs->$#*];
        return unless @value_inputs;

        # Get the result type
        my $phi_type = $type_map->{$node->id};
        return unless defined $phi_type;

        # Check all incoming values have types
        my @incoming_types;
        for my $input_id (@value_inputs) {
            my $input_type = $type_map->{$input_id};
            unless (defined $input_type) {
                push $errors->@*, sprintf(
                    "Phi node %d has input %d with no type",
                    $node->id, $input_id
                );
                next;
            }
            push @incoming_types, $input_type;
        }

        # Check for Bottom types
        for my $i (0..$#incoming_types) {
            my $type = $incoming_types[$i];
            if ($type isa Chalk::IR::Type::Bottom) {
                push $errors->@*, sprintf(
                    "Phi node %d has Bottom type at input %d",
                    $node->id, $value_inputs[$i]
                );
            }
        }

        # Phi result should be Union if types differ, or the common type
        # This is already handled by TypePropagation, we just verify it
        if (@incoming_types > 1) {
            my $first_class = ref($incoming_types[0]);
            my $all_same = 1;
            for my $type (@incoming_types[1..$#incoming_types]) {
                if (ref($type) ne $first_class) {
                    $all_same = 0;
                    last;
                }
            }

            # If types differ, result should be Union or Top
            unless ($all_same) {
                unless ($phi_type isa Chalk::IR::Type::Union || $phi_type isa Chalk::IR::Type::Top) {
                    push $errors->@*, sprintf(
                        "Phi node %d has differing input types but result is not Union/Top: %s",
                        $node->id, ref($phi_type)
                    );
                }
            }
        }
    }

    # Check if a type is numeric (Integer, Float, or Union containing them)
    method _is_numeric_type($type) {
        return 1 if $type isa Chalk::IR::Type::Integer;
        return 1 if $type isa Chalk::IR::Type::Float;
        return 1 if $type isa Chalk::IR::Type::Top;  # Top is compatible with everything

        # Check Union types
        if ($type isa Chalk::IR::Type::Union) {
            # A Union is numeric if it contains Integer or Float
            return 1 if $type->contains(Chalk::IR::Type::Integer->TOP());
            return 1 if $type->contains(Chalk::IR::Type::Float->TOP());
        }

        return 0;
    }

    # Get validation errors
    method get_errors() {
        return [$errors->@*];  # Return copy
    }
}

1;
