# ABOUTME: Method, subroutine, or builtin call node in the Chalk IR.
# ABOUTME: Carries dispatch kind (method/sub/builtin) and callee name.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::Call :isa(Chalk::IR::Node) {
    field $dispatch_kind :param :reader;
    field $name          :param :reader;

    method operation() { 'Call' }

    method content_hash() {
        my @input_ids = map { $_->id() } $self->inputs()->@*;
        return "Call|dispatch_kind=" . $dispatch_kind
             . "|name=" . $name
             . "|" . join('|', @input_ids);
    }
}
