# ABOUTME: Reference node in the IR graph
# ABOUTME: Represents reference operator (\$var) - creates a reference to a variable
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Reference :isa(Chalk::IR::Node::Base) {
    field $operand_id :param :reader;

    method op() { 'Reference' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Reference',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand_id,
            },
        };
    }

    method execute($values) {
        # Reference creates a reference to a value
        # Returns a hash representing the reference (for future dereference support)
        # inputs[0] = control
        # inputs[1] = operand node (the value being referenced)
        my @inputs = $self->inputs->@*;
        my $control_id = $inputs[0];
        my $operand_node_id = $inputs[1];

        # Get the value being referenced
        my $operand_val = $values->{$operand_node_id};

        # Return a reference structure
        # This will be used by future Dereference operator
        return {
            ref_type => 'SCALAR',
            ref_to => $operand_node_id,
            value => $operand_val,
        };
    }
}

1;
