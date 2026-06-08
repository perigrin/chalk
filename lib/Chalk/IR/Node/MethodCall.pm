# ABOUTME: MethodCall IR node — vtable-slot dispatch on a class instance.
# ABOUTME: Inputs: [obj_node, ClassDecl_node, arg_1, ...]. Resolves method slot at lowering time.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::MethodCall :isa(Chalk::IR::Node) {
    # Name of the method to call (e.g. "greet", "name").
    # The emitter resolves the vtable slot index from this name at lowering time.
    # If the method is absent from the class's vtable, the emitter MUST die loudly.
    field $method_name :param :reader;

    method operation() { 'MethodCall' }

    method obj_node()        { return $self->inputs->[0] }
    method class_decl_node() { return $self->inputs->[1] }
    method arg_nodes()       {
        my $inp = $self->inputs;
        return [] unless defined $inp && scalar(@$inp) > 2;
        return [ @{$inp}[2 .. $#{$inp}] ];
    }

    method content_hash() {
        return join('|', 'MethodCall', "method_name=$method_name",
            $self->_serialize_inputs());
    }
}
