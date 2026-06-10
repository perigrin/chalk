# ABOUTME: New IR node — constructs a class instance (malloc + vtable bind + :param binding).
# ABOUTME: Inputs: [ClassInfo, param_val_1, param_val_2, ...] with param_name_i attrs.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::New :isa(Chalk::IR::Node) {
    # Ordered list of :param names matching inputs[1..N].
    # e.g. ['name'] means inputs[1] is bound to :param $name.
    # Empty for classes with no :param fields.
    field $param_names :param :reader = [];

    method operation() { 'New' }

    method class_decl_node() {
        # inputs[0] is the ClassInfo (or ClassDecl) node
        return $self->inputs->[0];
    }

    method param_values() {
        # inputs[1..N] are the values for each :param field (parallel to param_names)
        my $inp = $self->inputs;
        return [] unless defined $inp && scalar(@$inp) > 1;
        return [ @{$inp}[1 .. $#{$inp}] ];
    }

    method content_hash() {
        my $pnames = join(',', defined $param_names ? $param_names->@* : ());
        return join('|', 'New', "param_names=[$pnames]", $self->_serialize_inputs());
    }
}
