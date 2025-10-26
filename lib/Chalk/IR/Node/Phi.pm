# ABOUTME: Phi node in the IR graph
# ABOUTME: Represents SSA phi function that selects value based on control flow path
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Phi :isa(Chalk::IR::Node::Base) {
    field $region_id :param :reader;

    method op() { 'Phi' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Phi',
            inputs => $self->inputs,
            attributes => {
                region_id => $region_id,
            },
        };
    }
}

1;
