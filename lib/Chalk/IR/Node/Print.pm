# ABOUTME: print statement node in the Chalk IR: a control-pinned statement effect
# ABOUTME: that emits its list of value inputs to stdout and yields print's boolean 1.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::Print :isa(Chalk::IR::Node) {
    method operation() { 'Print' }

    method content_hash() {
        return join('|', 'Print', $self->_serialize_inputs());
    }
}
