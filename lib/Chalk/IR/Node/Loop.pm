# ABOUTME: Loop node in the IR graph
# ABOUTME: Represents loop control flow structure with entry and backedge inputs
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Loop :isa(Chalk::IR::Node::Base) {
    method op() { 'Loop' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Loop',
            inputs => $self->inputs,
            attributes => {},
        };
    }
}

1;
