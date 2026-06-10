# ABOUTME: FieldWrite IR node — stores a value into a field Slot of an object.
# ABOUTME: Inputs: [obj_node, new_value_node]. Field addressed by field_index attribute.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::FieldWrite :isa(Chalk::IR::Node) {
    # Zero-based field index (same as MOP::Field::fieldix).
    # The actual struct slot = field_index + 1 (after the vtable pointer).
    field $field_index :param :reader;

    method operation() { 'FieldWrite' }

    # In non-method-body context: inputs[0]=obj_node, inputs[1]=new_val_node.
    # In method-body context: inputs[0]=new_val_node (obj is implicit $self).
    method obj_node()     { return $self->inputs->[0] }
    method new_val_node() { return $self->inputs->[1] }

    method content_hash() {
        return join('|', 'FieldWrite', "field_index=$field_index",
            $self->_serialize_inputs());
    }
}
