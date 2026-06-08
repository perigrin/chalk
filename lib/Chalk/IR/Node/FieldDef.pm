# ABOUTME: FieldDef IR node — declares a field within a class in the Chalk IR.
# ABOUTME: Inputs: [optional_default_value_node]. ClassDecl.inputs includes this FieldDef.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::FieldDef :isa(Chalk::IR::Node) {
    # Field name without sigil (e.g. "name", "left", "val")
    field $field_name  :param :reader;

    # Zero-based index of this field in the object struct (after the vtable ptr).
    # Slot offset = field_index + 1 (accounting for the vtable pointer at slot 0).
    field $field_index :param :reader;

    # Whether this field is a :param (bound from constructor args)
    field $is_param    :param :reader = false;

    # Whether this field has a :reader accessor synthesized
    field $has_reader  :param :reader = false;

    # Whether this field has a compile-time default value
    field $has_default :param :reader = false;

    # Machine representation of the field's value ('Int', 'Str', 'Bool', 'Num', etc.)
    # Used by :reader synthesis to pick the correct vtable fn signature.
    # Defaults to 'Int' if not specified.
    field $field_repr  :param :reader = 'Int';

    method operation() { 'FieldDef' }

    # Optional default value node is inputs[0] (undef / empty inputs if no default)
    method default_node() { return $self->inputs->[0] }

    method content_hash() {
        my $fr = $field_repr // 'Int';
        return join('|', 'FieldDef',
            "field_name=$field_name",
            "field_index=$field_index",
            "is_param=" . ($is_param ? '1' : '0'),
            "has_reader=" . ($has_reader ? '1' : '0'),
            "has_default=" . ($has_default ? '1' : '0'),
            "field_repr=$fr",
            $self->_serialize_inputs());
    }
}
