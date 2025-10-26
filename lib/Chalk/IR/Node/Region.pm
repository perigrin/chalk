# ABOUTME: Region node in the IR graph
# ABOUTME: Represents control flow merge point where multiple paths converge
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Region :isa(Chalk::IR::Node::Base) {
    method op() { 'Region' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Region',
            inputs => $self->inputs,
            attributes => {},
        };
    }
}

1;
