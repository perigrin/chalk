# ABOUTME: ClassDecl IR node for a feature-class declaration in the Chalk IR.
# ABOUTME: Carries class name, parent name, and serves as identity anchor for object layout + vtable.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::ClassDecl :isa(Chalk::IR::Node) {
    # Human-readable class name (e.g. "Greeter")
    field $class_name :param :reader;

    # Optional parent class name string (undef = no parent).
    # Used for compile-time MRO flattening at lowering time.
    field $parent_name :param :reader = undef;

    method operation() { 'ClassDecl' }

    method content_hash() {
        my $pn = defined $parent_name ? $parent_name : 'undef';
        return join('|', 'ClassDecl', "class_name=$class_name", "parent_name=$pn",
            $self->_serialize_inputs());
    }
}
