# ABOUTME: print statement node in the Chalk IR: a control-pinned statement effect
# ABOUTME: that emits its list of value inputs to stdout and yields print's boolean 1.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node::Print :isa(Chalk::IR::Node) {
    method operation() { 'Print' }
    method staleness_kind() { 'opaque' }

    # FIXED: writes to stdout -- a statement effect in ANY context
    method is_fixed() { return true }

    # `print $fh LIST`: the first input is the handle, not a value printed.
    field $has_filehandle :reader = 0;

    method set_has_filehandle($b) {
        $has_filehandle = $b ? 1 : 0;
        return;
    }

    method content_hash() {
        return join('|', 'Print', ($has_filehandle ? 'fh' : ()), $self->_serialize_inputs());
    }
}
