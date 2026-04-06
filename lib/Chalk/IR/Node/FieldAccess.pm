# ABOUTME: IR node for accessing a class field by index and stash (package) name.
# ABOUTME: Used to represent reads of Perl 5.42 class fields in the Sea of Nodes graph.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Access;

class Chalk::IR::Node::FieldAccess :isa(Chalk::IR::Node::Access) {
    field $field_index :param :reader;
    field $field_stash :param :reader;

    method operation() { 'FieldAccess' }

    method content_hash() {
        return join('|', 'FieldAccess', "field_index=$field_index", "field_stash=$field_stash", $self->_serialize_inputs());
    }
}
